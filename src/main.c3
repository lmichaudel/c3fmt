module c3fmt;

import std::core::mem;

<*
 Format C3 source code using a specified configuration.

 @param allocator : "Allocator to be used for the formatted result."
 @param string : "C3 source code."
 @param config : "Configuration to be used."
*>
fn String? format_string(Allocator allocator, String string, Config config = default_config(), bool check_semantic = false) {
    C3Fmt formatter = c3fmt::new(string, config);
    defer formatter.free();

    formatter.format(check_semantic)!;

    return formatter.dstr_buf.copy_str(allocator);
}

module c3fmt::executable;

import c3fmt;
import std::io;

import c3fmt::printer;
import opt;

fn String? read_file(String file_name) {
    File fh = file::open(file_name, "rb")!;
    defer (void)fh.close();

    String content = (String)file::load(mem, file_name)!;
    return content;
}

struct CLIOptions {
    bool need_help;
    bool in_place;
    bool stdout;
    bool stdin;
}
CLIOptions cli_options;

fn int main(String[] args)
{
    bool version_asked;
    int? arg_last_parsed = opt::@parse(
        args,
        "h*", "help",     null,
        "v",  "version",  &version_asked,
        null, "in-place", &cli_options.in_place,
        null, "stdin",    &cli_options.stdin,
        null, "stdout",   &cli_options.stdout
    );

    if (catch err = arg_last_parsed) {
        switch (err)
        {
            case opt::HELP_REQUESTED:
            case opt::MISSING_ARGUMENT:
            case opt::ILLEGAL_OPTION:
                io::printfn("Usage: c3fmt [<options>] <files>");
                io::printf("\n");
                io::printfn("Options:");
                io::printfn("\t-h, --help       - Show this help.");
                io::printfn("\t-v, --version    - Show current version.");
                io::printfn("\t--in-place       - Format files in place.");
                io::printfn("\t--stdin          - Read input from stdin.");
                io::printfn("\t--stdout         - Output result to stdout.");
                return 1;
            default:
                return 1;
        }
    }

    if(version_asked) {
        io::printfn("c3fmt version:     \t0.0.1");
        io::printfn("target c3c version:\t0.7.8");
    }

    if(arg_last_parsed == args.len) {
        io::printfn("No input file provided.");
        return 1;
    }

    if(cli_options.stdin) {
        io::printfn("Read from stdin is not yet supported.");
        return 1;
    }

    if(!cli_options.in_place) {
        cli_options.stdout = true;
    }

    for(int i = arg_last_parsed; i < args.len; ++i) {
        String? content = read_file(args[i]);
        defer (void)content.free(mem);
        if (catch excuse = content) {
            io::eprintfn("Error: could not read file %s.", args[1]);
            io::eprintfn("Excuse: %s.", excuse);
            return 1;
        }

        String? formatted = c3fmt::format_string(mem, content);
        defer (void)formatted.free(mem);
        if (catch excuse = formatted) {
            io::eprintfn("Error: could not format source code.");
            io::eprintfn("Excuse: %s.", excuse);
            return 1;
        }

        if(cli_options.stdout) {
            io::printfn("%s", formatted);
        }
    }

	return 0;
}