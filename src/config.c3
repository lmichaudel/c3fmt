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
	bool newline_at_eof;

	uint spaces_before_trailing_comment;

	bool align_assignments;
	bool align_comments;
	bool align_string_concat;
}

fn Config default_config()
{
	return {
		.use_tabs = true,
		.tab_size = 4,
		.indent_width = 4,
		.max_blank_line_between_statements = 2,
		.max_line_length = 120,
		.brace_style = ALLMAN,
		.else_on_newline = true,
		.newline_at_eof = false,
		.spaces_before_trailing_comment = 1,
		.align_assignments = true,
		.align_comments = true,
		.align_string_concat = false,
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

	String content = (String)file::load(tmem, file_path)!;
	String[] lines = content.split(tmem, "\n");

	foreach (raw_line : lines)
	{
		sz comment_start_id = raw_line.index_of_char('#') ?? raw_line.len;
		String line = raw_line[:comment_start_id].trim();

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
				conf.tab_size = (uint)val.to_int()!;
			case "indent_width":
				conf.indent_width = (uint)val.to_int()!;

			case "max_blank_line_between_statements":
				conf.max_blank_line_between_statements = (uint)val.to_int()!;
			case "max_line_length":
				conf.max_line_length = (uint)val.to_int()!;

			case "brace_style":
				if (val == "ALLMAN")
				{
					conf.brace_style = ALLMAN;
				}
				else if (val == "K&R")
				{
					conf.brace_style = K_AND_R;
					conf.else_on_newline = false;
				}
				else
				{
					return INVALID_CONFIG~;
				}
			case "else_on_newline":
				conf.else_on_newline = val.to_bool()!;
			case "newline_at_eof":
				conf.newline_at_eof = val.to_bool()!;
			case "spaces_before_trailing_comment":
				conf.spaces_before_trailing_comment = (uint)val.to_int()!;
			case "align_assignments":
				conf.align_assignments = val.to_bool()!;
			case "align_comments":
				conf.align_comments = val.to_bool()!;
			case "align_string_concat":
				conf.align_string_concat = val.to_bool()!;

			default:
				return INVALID_CONFIG~;
		}
	}

	return conf;
}
