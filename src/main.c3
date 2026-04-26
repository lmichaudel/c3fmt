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

<* c3fmt executable entry point *>
module c3fmt::executable;

import c3fmt;
import opt;
import std;
import libc;

alias FileList = List { String };

struct CLIOptions
{
	bool need_help;
	bool in_place;
	bool stdout;
	bool stdin;
	String config;
	bool force_default_config;
	bool check;
}

CLIOptions cli_options;

struct Context
{
	Config config;
	Mutex print_mu;
	bool has_mismatch;
}

fn void format_worker(any[] args)
{
	String path = *(String*)args[0].ptr;
	Config config = *(Config*)args[1].ptr;
	Context* ctx = *(Context**)args[2].ptr;
	if (catch excuse = format_file(path, config, ctx))
	{
		io::eprintfn("Error: could not format file %s: %s.", path, excuse);
	}
}

fn int main(String[] args)
{
	Context ctx;
	if (catch err = ctx.print_mu.init())
	{
		io::eprintfn("Mutex error: %s.", err);
		return 1;
	}

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
		&cli_options.force_default_config, //
		null,
		"check",
		&cli_options.check
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
				io::printfn("\t--check          - Finish with error if files are not formatted.");
				return 1;
			default:
				return 1;
		}
	}

	if (version_asked)
	{
		io::printfn("c3fmt version:     \t0.2.4");
		io::printfn("target c3c version:\t0.8.0");
		return 0;
	}

	Config config = c3fmt::default_config();
	if (cli_options.config != "")
	{
		Config? parsed = c3fmt::parse_from_file(cli_options.config);

		if(catch err = parsed)
		{
			io::eprintfn("Error with config file '%s' (%s)", cli_options.config, err);
			return 1;
		}

		config = parsed;
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
		defer formatted.free(mem)!!;

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

	if (!cli_options.in_place && !cli_options.stdout && !cli_options.check)
	{
		cli_options.stdout = true;
	}

	ctx.config = config;
	ctx.has_mismatch = false;

	FileList files;
	files.init(mem, 512);
	defer {
		foreach (f : files) f.free(mem);
		files.free();
	}

	for (int i = arg_last_parsed; i < args.len; ++i)
	{
		String entry = args[i];
		fast_scan(entry, &files);
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

	return ctx.has_mismatch ? 1 : 0;
}

fn void fast_scan(String entry, FileList* files)
{
	if (!io::path::is_dir(io::path::temp(entry)!!))
	{
		files.push(entry.copy(mem));
		return;
	}

	DString path_buf = dstring::new(mem);
	defer path_buf.free();
	path_buf.append(entry);

	fast_scan_recursive(&path_buf, files);
}

fn void fast_scan_recursive(DString* path_buf, FileList* files)
{
	usz original_len = path_buf.len();
	String current_path = path_buf.str_view();

	$if env::POSIX:
		DIRPtr dir = posix::opendir(current_path.zstr_tcopy());
		if (!dir) return;
		defer posix::closedir(dir);

		while (Posix_dirent* entry = posix::readdir(dir))
		{
			String name = ((ZString)&entry.name).str_view();
			if (name == "." || name == "..") continue;

			(*path_buf).chop(original_len);
			if (path_buf.len() > 0 && (*path_buf)[path_buf.len() - 1] != '/') path_buf.append('/');
			path_buf.append(name);

			if (entry.d_type == posix::DT_DIR)
			{
				fast_scan_recursive(path_buf, files);
			}
			else if (entry.d_type == posix::DT_REG || entry.d_type == posix::DT_UNKNOWN)
			{
				if (path_buf.str_view().ends_with(".c3"))
				{
					if (entry.d_type == posix::DT_UNKNOWN && !io::path::is_file(io::path::temp(path_buf.str_view())!!))
					{
						if (io::path::is_dir(io::path::temp(path_buf.str_view())!!))
						{
							fast_scan_recursive(path_buf, files);
						}
						continue;
					}
					files.push(path_buf.str_view().copy(mem));
				}
			}
		}
	$else
		// Fallback to standard traverse for non-POSIX (Windows handling would be more complex)
		(void)io::path::traverse(io::path::temp(current_path)!!, &collect_callback, files);
	$endif
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

	Mutex.@in_lock(&ctx.print_mu)
	{
		if (catch excuse = content)
		{
			io::eprintfn("Error: could not read file %s: %s", path, excuse);
			return excuse~;
		}

		String? formatted = c3fmt::format_string(mem, content, config);
		defer (void)formatted.free(mem);

		if (catch excuse = formatted)
		{
			io::eprintfn("Error: could not format file %s: %s.", path, excuse);
			return excuse~;
		}

		switch
		{
			case cli_options.in_place:
				if (catch excuse = file::save(path, formatted))
				{
					io::eprintfn("Error: could not write to file %s: %s", path, excuse);
					return excuse~;
				}
			case cli_options.stdout:
				io::printfn("%s", formatted);
			case cli_options.check:
				if (content != formatted)
				{
					io::eprintfn("Format mismatch: %s", path);

					// Show diff if possible
					if (try p = process::spawn({"diff", "--unified=0", "-p", "--color=always", "--label", path, "--label", "formatted", path, "-"}))
					{
						(void)p.write_stdin(formatted);
						// Close stdin to signal end of input
						libc::fclose(p.stdin_file);
						p.stdin_file = null;

						char[1024] buf;
						while (try len = p.read_stdout(&buf, buf.len))
						{
							if (len == 0) break;
							io::print((String)buf[:len]);
						}
						(void)p.join();
						p.destroy();
					}

					ctx.has_mismatch = true;
				}
			default:
		}

	};
	return;
}
