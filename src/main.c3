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
import std::os::argparse;
import std;
import libc;

alias FileList = List { String };

struct CLIOptions
{
	bool need_help;
	bool in_place;
	bool stdout;
	bool stdin;
	String stdin_filepath;
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

faultdef CONFIG_NOT_FOUND;

<*
 Walk upward from `start` looking for the nearest .c3fmt file.
 Returns CONFIG_NOT_FOUND if the walk reaches root without a match.
 @param start : "Current file, or directory path."
*>
fn Config? find_config(String start) @local => @pool()
{
	Path dir = start.to_absolute_path(tmem)!.dirname().to_tpath()!;

	while (true)
	{
		Path candidate = dir.tappend(".c3fmt")!;
		if (file::exists(candidate))
		{
			return c3fmt::parse_from_file((String)candidate)!;
		}

		Path? parent = dir.parent();
		if (catch parent) break;
		dir = parent;
	}

	return CONFIG_NOT_FOUND~;
}

fn Config resolve_config_for_file(String path, Config default_config) @local
{
	if (cli_options.config != "" || cli_options.force_default_config)
	{
		return default_config;
	}
	return find_config(path) ?? default_config;
}

fn void format_worker(any[] args)
{
	String path = *(String*)args[0].ptr;
	Config config = *(Config*)args[1].ptr;
	Context* ctx = *(Context**)args[2].ptr;
	if (catch exc = format_file(path, config, ctx))
	{
		io::eprintfn("Error: could not format file %s: %s.", path, exc);
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
	String[4096] positional_files;
	// c3fmt off
	sz? arg_last_parsed = argparse::@parse(
		args, //
		"h*", "help*",          "Show this help.", &cli_options.need_help,
		"v",  "version",        "Show current version.", &version_asked,
		"i",  "in-place",       "Format files in place.", &cli_options.in_place,
		      "stdin",          "Read input from stdin.", &cli_options.stdin,
		      "stdin-filepath", "File path hint for stdin mode (used to find .c3fmt config).", &cli_options.stdin_filepath,
		      "stdout",         "Output result to stdout.", &cli_options.stdout,
		"c",  "config",         "Specify a config file.", &cli_options.config,
		      "default",        "Force default config.", &cli_options.force_default_config,
		      "check",          "Finish with error if files are not formatted.", &cli_options.check,
		&positional_files
	);
	// c3fmt on

	if (catch err = arg_last_parsed)
	{
		switch (err)
		{
			case argparse::HELP_REQUESTED:
				io::printn();
				io::printfn("┌─────────────────────────────────────────────────────┐");
				io::printfn("│ Code formatter for the C3 language                  │");
				io::printfn("├─────────────────────────────────────────────────────┤");
				io::printfn("│ Author: Lucas Michaudel <lucas.michaudel@gmail.com> │");
				io::printfn("│ Repository: https://github.com/lmichaudel/c3fmt     │");
				io::printfn("└─────────────────────────────────────────────────────┘");
				io::printn();
				return 0;
			case argparse::MISSING_ARGUMENT:
				io::eprintfn("c3fmt: Option '%s%s' requires an argument.", argparse::last_opt.len > 1 ? "--" : "-", argparse::last_opt);
				io::eprintfn("Try '-h' or '--help' for usage information.");
				return 1;
			case argparse::ILLEGAL_OPTION:
				io::eprintfn("c3fmt: Unrecognized option '%s%s'.", argparse::last_opt.len > 1 ? "--" : "-", argparse::last_opt);
				io::eprintfn("Try '-h' or '--help' for usage information.");
				return 1;
			default:
				return 1;
		}
	}

	if (version_asked)
	{
		io::printfn("c3fmt version:     \t%s", env::PROJECT_VERSION);
		io::printfn("target c3c version:\t0.8.3");
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
	else
	{
		String search_dir = cli_options.stdin_filepath != "" ? cli_options.stdin_filepath : ".";

		Config? found = find_config(search_dir);
		if (try found)
		{
			config = found;
		}
		else if (@catch(found) != CONFIG_NOT_FOUND)
		{
			io::eprintfn("Can't parse .c3fmt configuration file: %s", @catch(found));
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

			sz s = io::stdin().read(buffer)!!;

			if (s == 0)
			{
				break;
			}

			read.append((String)buffer[:s]);
		}

		String? formatted = c3fmt::format_string(mem, read.str_view(), config);
		defer formatted.free(mem)!!;

		if (catch exc = formatted)
		{
			io::eprintfn("Error: could not format source code: %s.", exc);
			return 1;
		}

		io::printfn("%s", formatted);
		return 0;
	}

	if (positional_files[0] == "")
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

	foreach (entry : positional_files)
	{
		if (entry == "") break;
		fast_scan(entry, &files);
	}

	if (files.len() == 0) return 0;

	FixedThreadPool pool;
	ThreadSettings settings = { .stack_size = 8388608 };
	pool.init(os::num_cpu(), files.len(), settings)!!;
	defer (void)pool.destroy();

	foreach (path : files)
	{
		Config file_config = resolve_config_for_file(path, config);
		pool.push(&format_worker, path, file_config, &ctx)!!;
	}
	pool.join();

	return ctx.has_mismatch ? 1 : 0;
}

fn void fast_scan(String entry, FileList* files)
{
	if (!io::path::is_dir(io::path::tnew(entry)!!))
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
	sz original_len = path_buf.len();
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
					if (entry.d_type == posix::DT_UNKNOWN && !io::path::is_file(io::path::tnew(path_buf.str_view())!!))
					{
						if (io::path::is_dir(io::path::tnew(path_buf.str_view())!!))
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
		(void)io::path::traverse(io::path::tnew(current_path)!!, &collect_callback, files);
	$endif
}

fn bool? collect_callback(io::path::Path p, bool is_dir, any data)
{
	if (is_dir) return false;
	if (!p.has_extension("c3")) return false;

	FileList* files = (FileList*)data;
	files.push((String)p.copy(mem));
	return false;
}


fn void? format_file(String path, Config config, Context* ctx)
{
	String? content = (String)file::load(mem, path);
	defer (void)content.free(mem);

	Mutex.@in_lock(&ctx.print_mu)
	{
		if (catch exc = content)
		{
			io::eprintfn("Error: could not read file %s: %s", path, exc);
			return exc~;
		}

		String? formatted = c3fmt::format_string(mem, content, config);
		defer (void)formatted.free(mem);

		if (catch exc = formatted)
		{
			io::eprintfn("Error: could not format file %s: %s.", path, exc);
			return exc~;
		}

		switch
		{
			case cli_options.in_place:
				if (catch exc = file::save(path, formatted))
				{
					io::eprintfn("Error: could not write to file %s: %s", path, exc);
					return exc~;
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
