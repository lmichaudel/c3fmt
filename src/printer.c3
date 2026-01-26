module c3fmt::token;

enum TokenKind
{
	EOF,
	NEWLINE,
	SPACE,
	INDENT,
	DEDENT,
	TEXT,
	BEGIN_WRAP_GROUP,
	WRAP_POINT,
	INLINE_COMMENT,
}

// IMPLIED means if one wrap point of the same group was taken,
// this one should be taken too for style
// But forced wrap with line comments reset wrap group
// SUPER_IMPLIED acts the same but is taken even if the wrap was forced by
// a line comment.
enum WrapMode
{
	IMPLIED,
	SUPER_IMPLIED
}

struct WrapPoint
{
	WrapMode mode;
	usz indent;
}

struct Token
{
	TokenKind kind;
	String str;

	WrapPoint wrap_point;
}

fn Token eof()
{
	return (Token) { .kind = EOF };
}

fn Token newline()
{
	return (Token) { .kind = NEWLINE };
}

fn Token space()
{
	return (Token) { .kind = SPACE };
}

fn Token indent()
{
	return (Token) { .kind = INDENT };
}

fn Token dedent()
{
	return (Token) { .kind = DEDENT };
}

fn Token text(String text)
{
	return (Token) { .kind = TEXT, .str = text };
}

fn Token inline_comment(String text)
{
	return (Token) { .kind = INLINE_COMMENT, .str = text };
}

fn Token begin_wrap_group()
{
	return (Token) { .kind = BEGIN_WRAP_GROUP };
}

fn Token wrap_point(WrapPoint wrap_point)
{
	return (Token) { .kind = WRAP_POINT, .wrap_point = wrap_point };
}

fn bool Token.is(&self, TokenKind kind)
{
	return self.kind == kind;
}

fn usz Token.len(&self)
{
	switch (self.kind)
	{
		case EOF:
		case NEWLINE:
		case INDENT:
		case DEDENT:
		case BEGIN_WRAP_GROUP:
		case WRAP_POINT:
			return 0;
		case SPACE:
			return 1;
		case TEXT:
			return self.str.len;
		case INLINE_COMMENT:
			return self.str.len + 3;
	}
}

fn String Token.print(&self)
{
	switch (self.kind)
	{
		case WRAP_POINT:
		case EOF:
			return "";
		case NEWLINE:
			return "\n";
		case SPACE:
			return " ";
		case TEXT:
			return self.str;
		case INLINE_COMMENT:
			return self.str;
		case BEGIN_WRAP_GROUP:
			unreachable();
		case INDENT:
			unreachable();
		case DEDENT:
			unreachable();
	}
}

module c3fmt::printer;

import std::collections::list;
import std::io;
import c3fmt::token;

alias TokenBuffer = List{Token};

fn void C3Fmt.trim(&self)
{
	if (self.buf.len() == 0)
	{
		return;
	}

	TokenBuffer new_buf;
	new_buf.init(mem);
	new_buf.push(self.buf[0]);

	for (usz i = 1; i < self.buf.len(); ++i)
	{
		if (self.buf[i].kind == NEWLINE)
		{
			int j = (int)i - 1;
			while (j >= 0 && self.buf[j].kind == SPACE)
			{
				(void)new_buf.pop();
				j--;
			}
		}
		if (self.buf[i].kind == EOF)
		{
			int j = (int)i - 1;
			while (j >= 0 && (self.buf[j].kind == SPACE || self.buf[j].kind == NEWLINE))
			{
				(void)new_buf.pop();
				j--;
			}
		}

		new_buf.push(self.buf[i]);
	}

	self.buf.free();
	self.buf = new_buf;
}

fn void C3Fmt.print(&self)
{
	self.trim();

	usz token_count = self.buf.len();
	if (token_count == 0)
	{
		return;
	}

	usz indent_level = 0;
	for (usz i = 0, usz j = 0; j < token_count; ++j)
	{
		switch (self.buf[j].kind)
		{
			case NEWLINE:
				assert (i <= j);
				self.print_line(self.buf.array_view()[i..j], indent_level);
				i = j + 1;
				while (self.buf[i].kind == INDENT || self.buf[i].kind == DEDENT)
				{
					i++;
				}
			case EOF:
				assert (i <= j);
				self.print_line(self.buf.array_view()[i..j], indent_level);
			case INDENT:
				indent_level++;
			case DEDENT:
				assert (indent_level > 0);
				indent_level--;
			default:
		}
	}
}

fn void C3Fmt.print_indent(&self)
{
	if (self.config.use_tabs)
	{
		self.dstr_buf.append('\t');
	}
	else
	{
		for (usz i = 0; i < self.config.indent_width; ++i)
		{
			self.dstr_buf.append(' ');
		}
	}
}

fn void C3Fmt.print_line(&self, Token[] tokens, usz indent_level)
{
	if (tokens.len == 1 && tokens[0].kind == NEWLINE)
	{
		self.dstr_buf.append('\n');
		return;
	}

	usz line_length = 0;
	if (self.config.use_tabs)
	{
		line_length += self.config.tab_size;
	}
	else
	{
		line_length += self.config.indent_width;
	}

	foreach (token : tokens)
	{
		line_length += token.len();
	}

	for (usz i = 0; i < indent_level; ++i)
	{
		self.print_indent();
	}

	bool force_take_wrap_point = false;
	bool wrap_point_needed = self.config.max_line_length > 0 && line_length > self.config.max_line_length;

	bool took_one_wp_in_group = false;
	bool took_one_forced_wp_in_group = false;
	foreach (id, token : tokens)
	{
		if (token.kind == BEGIN_WRAP_GROUP)
		{
			took_one_wp_in_group = false;
			took_one_forced_wp_in_group = false;
			continue;
		}

		// Finding an inline comment forces wrap
		// if there is a wrap point just after
		// otherwise it's just a very formatting from the user
		// like:
		// int a = 10 // i'm a psycho
		// ;
		if (token.kind == INLINE_COMMENT)
		{
			self.dstr_buf.append("//");
			if (token.str != "")
			{
				self.dstr_buf.append(" ");
			}
			self.dstr_buf.append(token.print());
			self.dstr_buf.append('\n');
			force_take_wrap_point = true;
			continue;
		}

		// skip space
		if (token.kind == SPACE && force_take_wrap_point)
		{
			continue;
		}
		if (token.kind != WRAP_POINT)
		{
			force_take_wrap_point = false;
		}

		if (force_take_wrap_point)
		{
			for (usz i = 0; i < indent_level + token.wrap_point.indent; ++i)
			{
				self.print_indent();
			}

			// Also recalculate our length after this wrap
			usz new_line_length = 0;
			if (self.config.use_tabs)
			{
				line_length += self.config.tab_size * (indent_level + token.wrap_point.indent);
			}
			else
			{
				line_length += self.config.indent_width * (indent_level + token.wrap_point.indent);
			}

			foreach (remaining_token : tokens[id + 1..])
			{
				line_length += token.len();
			}

			wrap_point_needed = new_line_length > self.config.max_line_length;
			took_one_wp_in_group = false;
			took_one_forced_wp_in_group = true;
			// took_one_wp_in_group = false; // reset the group too
		}
		else
		{
			if (token.kind == WRAP_POINT)
			{
				if (wrap_point_needed || ((token.wrap_point.mode == IMPLIED || token.wrap_point.mode == SUPER_IMPLIED) && took_one_wp_in_group) || (token.wrap_point.mode == SUPER_IMPLIED && took_one_forced_wp_in_group))
				{
					took_one_wp_in_group = true;

					while (self.dstr_buf[self.dstr_buf.len() - 1] == ' ')
					{
						self.dstr_buf.chop(self.dstr_buf.len() - 1);
					}

					self.dstr_buf.append('\n');
					for (usz i = 0; i < indent_level + token.wrap_point.indent; ++i)
					{
						self.print_indent();
					}

					// Calculate what is the size of the remaining tokens
					// after this wrap.
					usz new_line_length = 0;
					if (self.config.use_tabs)
					{
						line_length += self.config.tab_size * (indent_level + token.wrap_point.indent);
					}
					else
					{
						line_length += self.config.indent_width * (indent_level + token.wrap_point.indent);
					}

					foreach (remaining_token : tokens[id + 1..])
					{
						line_length += token.len();
					}

					wrap_point_needed = new_line_length > self.config.max_line_length;
				}
			}
			else
			{
				if (token.kind == INLINE_COMMENT)
				{
					self.dstr_buf.append("//");
					if (token.str != "")
					{
						self.dstr_buf.append(" ");
					}
				}
				self.dstr_buf.append(token.print());
			}
		}
	}
}

fn void TokenBuffer.eof(&self)
{
	self.push(token::eof());
}

fn void TokenBuffer.newline(&self)
{
	self.push(token::newline());
}

fn void TokenBuffer.space(&self)
{
	self.push(token::space());
}

fn void TokenBuffer.indent(&self)
{
	self.push(token::indent());
}

fn void TokenBuffer.dedent(&self)
{
	self.push(token::dedent());
}

fn void TokenBuffer.text(&self, String text)
{
	self.push(token::text(text));
}

fn void TokenBuffer.inline_comment(&self, String text)
{
	self.push(token::inline_comment(text));
}

fn void TokenBuffer.begin_wrap_group(&self)
{
	self.push(token::begin_wrap_group());
}

fn void TokenBuffer.wrap_point(&self, WrapPoint wrap_point)
{
	self.push(token::wrap_point(wrap_point));
}

fn bool TokenBuffer.gobble_last_newline(&self)
{
	if (self.len() > 0)
	{
		if (self.last()!!.kind == NEWLINE)
		{
			self.pop()!!;
			return true;
		}
	}

	return false;
}
