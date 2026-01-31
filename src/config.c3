module c3fmt;

enum BraceStyle
{
	ALLMAN,
	K_AND_R
}

struct Config
{
	bool use_tabs;
	uint tab_size;
	uint indent_width;

	uint max_blank_line_between_statements;
	uint max_line_length;

	BraceStyle brace_style;
	bool else_on_newline;
}

fn Config default_config()
{
    return {
        .use_tabs = true,
        .tab_size = 4,
        .indent_width = 4,

        .max_blank_line_between_statements = 2,
        .max_line_length = 0,

        .brace_style = ALLMAN,
        .else_on_newline = true,
    };
}

import std::io::file;


faultdef INVALID_CONFIG;

fn bool? String.to_bool(self)
{
	if (self == "true")
	{
		return true;
	}
	if (self == "false")
	{
		return false;
	}

	return INVALID_CONFIG~;
}

fn Config? parse_from_file(String file_path) => @pool()
{
	Config conf = default_config();

	String content = (String)file::load(mem, file_path)!;
	String[] lines = content.split(tmem, "\n");

	foreach (raw_line : lines)
	{
		usz comment_start_id = raw_line.index_of_char('#') ?? raw_line.len;
		String line = raw_line[:comment_start_id];

		if (line == "")
		{
			continue;
		}

		String[] vals = line.split(tmem, ":");

		if (vals.len != 2)
		{
			io::eprintfn("Invalid line :");
			io::eprintfn("%s", raw_line);
			return INVALID_CONFIG~;
		}

		String key = vals[0].trim();
		String val = vals[1].trim();

		switch (key)
		{
			case "use_tabs":
				conf.use_tabs = val.to_bool()!;
			case "tab_size":
				conf.tab_size = val.to_int()!;
			case "indent_width":
				conf.indent_width = val.to_int()!;

			case "max_blank_line_between_statements":
				conf.max_blank_line_between_statements = val.to_int()!;
			case "max_line_length":
				conf.max_line_length = val.to_int()!;

			case "brace_style":
				if (val == "ALLMAN")
				{
					conf.brace_style = ALLMAN;
				}
				else if (val == "K&R")
				{
					conf.brace_style = K_AND_R;
				}
				else
				{
					return INVALID_CONFIG~;
				}
			case "else_on_newline":
				conf.else_on_newline = val.to_bool()!;

			default:
				return INVALID_CONFIG~;
		}
	}

	return conf;
}
