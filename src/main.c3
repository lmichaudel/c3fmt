module c3fmt;

import std::core::mem;

<*
 Format C3 source code using a specified configuration.
 @param allocator : "Allocator to be used for the formatted result."
 @param string : "C3 source code."
 @param config : "Configuration to be used."
*>
fn String? format_string(
	Allocator allocator,
	String string,
	Config config = default_config(),
	bool check_semantic = false
)
{
	C3Fmt formatter = c3fmt::new(string, config)!;
	defer formatter.free();

	formatter.format(check_semantic)!;

	return formatter.dstr_buf.copy_str(allocator);
}

module c3fmt::executable;

import c3fmt;
import opt;
import std::io;
import std::thread;
import std::os;
import std::collections::list;

alias FileList = List { String };

struct CLIOptions
{
	bool need_help;
	bool in_place;
	bool stdout;
	bool stdin;
	String config;
	bool force_default_config;
}

CLIOptions cli_options;

struct Context
{
	Config config;
	thread::Mutex print_mu;
}

fn void format_worker(any[] args)
{
	String path = *(String*)args[0].ptr;
	Config config = *(Config*)args[1].ptr;
	Context* ctx = *(Context**)args[2].ptr;
	(void)format_file(path, config, ctx);
}

fn int main(String[] args)
{
	bool version_asked;
	// c3fmt off
	int? arg_last_parsed = opt::@parse(//
		args, //
		"h*",
		"help",
		null, //
		"v",
		"version",
		&version_asked, //
		null,
		"in-place",
		&cli_options.in_place, //
		null,
		"stdin",
		&cli_options.stdin, //
		null,
		"stdout",
		&cli_options.stdout, //
		null,
		"config?",
		&cli_options.config, //
		null,
		"default",
		&cli_options.force_default_config
	);
	// c3fmt on

	if (catch err = arg_last_parsed)
	{
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
				io::printfn("\t--config=<path>  - Specify a config file.");
				io::printfn("\t--default        - Force default config.");
				return 1;
			default:
				return 1;
		}
	}

	if (version_asked)
	{
		io::printfn("c3fmt version:     \t0.2.0");
		io::printfn("target c3c version:\t0.7.9");
		return 0;
	}

	Config config = c3fmt::default_config();
	if (cli_options.config != "")
	{
		Config? parsed = c3fmt::parse_from_file(cli_options.config);

		if (try parsed)
		{
			config = parsed;
		}
		else
		{
			io::eprintfn("Can't find config file %s.", cli_options.config);
			return 1;
		}
	}
	else if (file::exists("./.c3fmt"))
	{
		Config? parsed = c3fmt::parse_from_file("./.c3fmt");

		if (try parsed)
		{
			config = parsed;
		}
		else
		{
			io::eprintfn(
				"Can't parse .c3fmt configuration file: %s",
				cli_options.config
			);
			return 1;
		}
	}

	if (cli_options.force_default_config)
	{
		config = c3fmt::default_config();
	}

	if (cli_options.stdin)
	{
		DString read = dstring::new(mem);
		defer read.free();

		while (true)
		{
			char[] buffer = mem::new_array(char, 512);
			defer free(buffer);

			usz s = io::stdin().read(buffer)!!;

			if (s == 0)
			{
				break;
			}

			read.append((String)buffer[:s]);
		}

		String? formatted = c3fmt::format_string(mem, read.str_view(), config);
		defer (void)formatted.free(mem);

		if (catch excuse = formatted)
		{
			io::eprintfn("Error: could not format source code: %s.", excuse);
			return 1;
		}

		io::printfn("%s", formatted);
		return 0;
	}

	if (arg_last_parsed == args.len)
	{
		io::eprintfn("No input file or directory provided.");
		return 1;
	}

	if (!cli_options.in_place && !cli_options.stdout)
	{
		cli_options.stdout = true;
	}

	Context ctx;
	ctx.config = config;
	ctx.print_mu.init()!!;
	defer (void)ctx.print_mu.destroy();

	FileList files;
	files.init(mem);
	defer {
		foreach (f : files) f.free(mem);
		files.free();
	}

	for (int i = arg_last_parsed; i < args.len; ++i)
	{
		String entry = args[i];
		if (io::path::is_dir(io::path::temp(entry)!!))
		{
			io::path::traverse(io::path::temp(entry)!!, &collect_callback, &files)!!;
		}
		else
		{
			files.push(entry.copy(mem));
		}
	}

	if (files.len() == 0) return 0;

	FixedThreadPool pool;
	pool.init(os::num_cpu(), queue_size: files.len())!!;
	defer (void)pool.destroy();

	foreach (path : files)
	{
		pool.push(&format_worker, path, config, &ctx)!!;
	}
	pool.join();

	return 0;
}

fn bool? collect_callback(io::path::Path p, bool is_dir, any data)
{
	if (is_dir) return false;
	if (!p.has_extension("c3")) return false;

	FileList* files = (FileList*)data;
	files.push(p.str_view().copy(mem));
	return false;
}


fn void? format_file(String path, Config config, Context* ctx)
{
	String? content = (String)file::load(mem, path);
	defer (void)content.free(mem);

	if (catch excuse = content)
	{
		ctx.print_mu.lock();
		io::eprintfn("Error: could not read file %s: %s", path, excuse);
		ctx.print_mu.unlock();
		return excuse~;
	}

	String? formatted = c3fmt::format_string(mem, content, config);
	defer (void)formatted.free(mem);

	if (catch excuse = formatted)
	{
		ctx.print_mu.lock();
		io::eprintfn(
			"Error: could not format file %s: %s.",
			path,
			excuse
		);
		ctx.print_mu.unlock();
		return excuse~;
	}

	if (cli_options.in_place)
	{
		if (catch excuse = file::save(path, formatted))
		{
			ctx.print_mu.lock();
			io::eprintfn(
				"Error: could not write to file %s: %s",
				path,
				excuse
			);
			ctx.print_mu.unlock();
			return excuse~;
		}
	}

	if (cli_options.stdout)
	{
		ctx.print_mu.lock();
		io::printfn("%s", formatted);
		ctx.print_mu.unlock();
	}
	return;
}
