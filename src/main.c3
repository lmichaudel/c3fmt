module c3fmt;

import std::core::mem;

<*
 Format C3 source code using a specified configuration.

 @param allocator : "Allocator to be used for the formatted result."
 @param string : "C3 source code."
 @param config : "Configuration to be used."
*>
fn String? format_string(Allocator allocator, String string, Config config = default_config()) {
    C3Fmt formatter = c3fmt::new(string, config);
    defer formatter.free();

    formatter.format()!;

    return formatter.dstr_buf.copy_str(allocator);
}

module c3fmt::executable;

import c3fmt;
import std::io;

import c3fmt::printer;

fn String? read_file(String file_name) {
    File fh = file::open(file_name, "rb")!;
    defer (void)fh.close();

    String content = (String)file::load(mem, file_name)!;
    return content;
}

fn int main(String[] args)
{
    if (args.len < 2)
    {
        io::eprintn("Usage: c3fmt <source_file> [--debug]");
        return 1;
    }

    String? content = read_file(args[1]);
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

    if(args.len < 3) {
        io::printfn("%s", formatted);
    }

	return 0;
}