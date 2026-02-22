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

struct WrapPoint
{
	usz indent;
	usz group_id;
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

fn Token begin_wrap_group(usz id)
{
	return (Token) { .kind = BEGIN_WRAP_GROUP, .wrap_point = {.group_id = id} };
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
		case BEGIN_WRAP_GROUP:
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

	// for debugging
	// foreach(tok : self.buf) {
	// 	switch(tok.kind) {
	// 		case NEWLINE:
	// 			io::printf("NL");
	// 		case EOF:
	// 			io::printf("EOF");
	// 		case TEXT:
	// 			io::printf("%s", tok.str);
	// 		case INDENT:
	// 			io::printf(">");
	// 		case DEDENT:
	// 			io::printf("<");
	// 		case INLINE_COMMENT:
	// 			io::printf("//");
	// 		case WRAP_POINT:
	// 			io::printf("WP");
	// 		case BEGIN_WRAP_GROUP:
	// 		case SPACE:
	// 	}
	// 	io::printf(" ");
	// }
	// io::printfn("");

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

fn usz C3Fmt.calculate_line_length(&self, Token[] tokens, usz indent_level) {
	usz line_length = 0;

	foreach (token : tokens)
	{
		line_length += token.len();
	}

	for (usz i = 0; i < indent_level; ++i)
	{
		if (self.config.use_tabs)
		{
			line_length += self.config.tab_size;
		}
		else
		{
			line_length += self.config.indent_width;
		}
	}

	return line_length;
}

fn void C3Fmt.print_line(&self, Token[] tokens, usz indent_level)
{
	if (tokens.len == 1 && tokens[0].kind == NEWLINE)
	{
		self.dstr_buf.append('\n');
		return;
	}

	usz line_length = self.calculate_line_length(tokens, indent_level);
	bool need_wrapping = self.config.max_line_length > 0 && line_length > self.config.max_line_length;
	bool need_processing = false;

	foreach(token : tokens) {
		if(token.kind == INLINE_COMMENT || token.kind == WRAP_POINT
		|| token.kind == BEGIN_WRAP_GROUP) {
			need_processing = true;
		}
	}

	if(need_processing) {
		usz i = 0;
		bool found_group = false;
		usz group_id = 0;
		bool took_one_wp = false;
		bool skip_next_space = false;
		usz next_indent_increase = 0;
		usz line_finish_indent_increase = 0;

		TokenBuffer new_buf;
		new_buf.init(mem);

		foreach (id, token : tokens)
		{
			switch(token.kind) {
				case BEGIN_WRAP_GROUP:
					if(!need_wrapping) {
						continue;
					}
					if(!found_group) {
						found_group = true;
						group_id = token.wrap_point.group_id;
					} else {
						new_buf.push(token);
					}
				case INLINE_COMMENT:
					new_buf.push(token::text("//"));
					if(token.str != "") {
						new_buf.push(token::space());
					}
					new_buf.push(token::text(token.str));
					new_buf.push(token::newline());
					skip_next_space = id < (tokens.len - 1) && tokens[id+1].kind == SPACE;

					self.print_line(new_buf.array_view()[i..], indent_level + next_indent_increase);
					i = new_buf.size;

					line_finish_indent_increase = 1;
					next_indent_increase = 1;
				case WRAP_POINT:
					if(!need_wrapping) {
						continue;
					}

					bool forced = false;
					if(new_buf.size > 2) {
						if(new_buf[^1].kind == NEWLINE
							|| (new_buf[^2].kind == NEWLINE && new_buf[^1].kind == SPACE))
						{
							forced = true;
						}
					}

					if(token.wrap_point.group_id != group_id) {
						new_buf.push(token);
						continue;
					}

					if(!forced) {
						new_buf.push(token::newline());
						self.print_line(new_buf.array_view()[i..], indent_level + next_indent_increase);
						i = new_buf.size;
					}

					line_finish_indent_increase = token.wrap_point.indent;
					next_indent_increase = 1;
					took_one_wp = true;
				case SPACE:
					if(!skip_next_space) {
						new_buf.push(token);
					} else {
						skip_next_space = false;
					}
				default:
					new_buf.push(token);
			}
		}

		self.print_line(new_buf.array_view()[i..], indent_level + line_finish_indent_increase);
		new_buf.free();
		return;
	}

	for (usz i = 0; i < indent_level; ++i)
	{
		self.print_indent();
	}

	foreach (id, token : tokens)
	{
		// trim one space
		if(token.kind == SPACE && (id < (tokens.len - 1) && tokens[id+1].kind == NEWLINE)) {
			continue;
		}
		self.dstr_buf.append(token.print());
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

fn usz TokenBuffer.begin_wrap_group(&self)
{
	static usz group_id = 0;
	group_id++;
	self.push(token::begin_wrap_group(group_id));

	return group_id;
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
