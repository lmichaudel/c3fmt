module c3fmt::token;

enum TokenKind {
    EOF,
    NEWLINE,
    SPACE,
    INDENT,
    DEDENT,
    TEXT,
    WRAP_POINT
}

enum WrapMode {
    NONE,
    BEFORE,
    AFTER
}

struct Token {
    TokenKind kind;
    String str;

    WrapMode wrap_mode;
    usz wrap_indent;
}

fn Token eof () {
    return (Token) { .kind = EOF };
}

fn Token newline() {
    return (Token) { .kind = NEWLINE };
}

fn Token space() {
    return (Token) { .kind = SPACE };
}

fn Token indent() {
    return (Token) { .kind = INDENT };
}

fn Token dedent() {
    return (Token) { .kind = DEDENT };
}

fn Token text(String text) {
    return (Token) { .kind = TEXT, .str = text };
}

fn Token wrap_point(WrapMode wrap_mode, usz wrap_indent = 1) {
    return (Token) {
        .kind = WRAP_POINT,
        .wrap_mode = wrap_mode,
        .wrap_indent = wrap_indent
    };
}

fn bool Token.is(&self, TokenKind kind) {
    return self.kind == kind;
}

fn usz Token.len(&self) {
    switch (self.kind) {
        case EOF:
        case NEWLINE:
        case INDENT:
        case DEDENT:
        case WRAP_POINT:
            return 0;
        case SPACE:
            return 1;
        case TEXT:
            return self.str.len;
    }
}

fn String Token.print(&self) {
    switch (self.kind) {
        case WRAP_POINT:
        case EOF:
            return "";
        case NEWLINE:
            return "\n";
        case SPACE:
            return " ";
        case TEXT:
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

fn void C3Fmt.trim(&self) {
    if(self.buf.len() == 0) {
        return;
    }

    TokenBuffer new_buf;
    new_buf.init(mem);
    new_buf.push(self.buf[0]);

    for (usz i = 1; i < self.buf.len(); ++i) {
        if(self.buf[i].kind == NEWLINE) {
            int j = (int)i - 1;
            while(j >= 0 && self.buf[j].kind == SPACE) {
                (void)new_buf.pop();
                j--;
            }
        }
        if(self.buf[i].kind == EOF) {
            int j = (int)i - 1;
            while(j >= 0 && (self.buf[j].kind == SPACE || self.buf[j].kind == NEWLINE)) {
                (void)new_buf.pop();
                j--;
            }
        }

        new_buf.push(self.buf[i]);
    }

    self.buf.free();
    self.buf = new_buf;
}

fn void C3Fmt.print(&self) {
    self.trim();

    usz token_count = self.buf.len();
    if(token_count == 0) {
        return;
    }

    usz indent_level = 0;
    for(usz i = 0, usz j = 0; j < token_count; ++j) {
        switch(self.buf[j].kind) {
            case NEWLINE:
                assert(i <= j);
                self.print_line(self.buf.array_view()[i..j], indent_level);
                i = j + 1;
                while(self.buf[i].kind == INDENT || self.buf[i].kind == DEDENT) {
                    i++;
                }
            case EOF:
                assert(i <= j);
                self.print_line(self.buf.array_view()[i..j], indent_level);
            case INDENT:
                indent_level++;
            case DEDENT:
                assert(indent_level > 0);
                indent_level--;
            default:
        }
    }
}

fn void C3Fmt.print_indent(&self) {
    if(self.config.use_tabs) {
        self.dstr_buf.append('\t');
    } else {
        for(usz i = 0; i < self.config.indent_width; ++i) {
            self.dstr_buf.append(' ');
        }
    }
}

fn void C3Fmt.print_line(&self, Token[] tokens, usz indent_level) {
    if(tokens.len == 1 && tokens[0].kind == NEWLINE) {
        self.dstr_buf.append('\n');
        return;
    }

    usz line_length = 0;
    if(self.config.use_tabs) {
        line_length += self.config.tab_size;
    } else {
        line_length += self.config.indent_width;
    }

    foreach(token : tokens) {
        line_length += token.len();
    }

    for(usz i = 0; i < indent_level; ++i) {
        self.print_indent();
    }

    if(self.config.max_line_length > 0 && line_length > self.config.max_line_length) {
        foreach(token : tokens) {
            // Before implementing a better solution,
            // let's just unwrap all points.
            if(token.wrap_mode == BEFORE) {
                self.dstr_buf.append('\n');
                for(usz i = 0; i < token.wrap_indent; ++i) {
                    self.dstr_buf.append('\t');
                }
            }

            self.dstr_buf.append(token.print());
        }
    } else {
        foreach(token : tokens) {
            self.dstr_buf.append(token.print());
        }
    }
}

fn void TokenBuffer.eof(&self) {
    self.push(token::eof());
}

fn void TokenBuffer.newline(&self) {
    self.push(token::newline());
}

fn void TokenBuffer.space(&self) {
    self.push(token::space());
}

fn void TokenBuffer.indent(&self) {
    self.push(token::indent());
}

fn void TokenBuffer.dedent(&self) {
    self.push(token::dedent());
}

fn void TokenBuffer.text(&self, String text) {
    self.push(token::text(text));
}

fn void TokenBuffer.wrap_point(&self, WrapMode wrap_mode, usz wrap_indent = 1) {
    self.push(token::wrap_point(wrap_mode, wrap_indent));
}