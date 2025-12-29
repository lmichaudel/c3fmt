/*
    Treesitter Helpers
*/
module ts;

fn uint TSNode.start_point_row(self) {
    TSPoint position = ts::node_start_point(self);
    return position.row;
}

fn uint TSNode.end_point_row(self) {
    TSPoint position = ts::node_end_point(self);
    return position.row;
}

fn TSNode TSNode.get_child_with_field(self, String field_name) {
    for(uint i = 0; i < ts::node_child_count(self); ++i) {
        if(ts::node_child(self, i).field_name() == field_name) {
            return ts::node_child(self, i);
        }
    }

    unreachable();
}

fn bool TSNode.has_child_of_type(self, String type) {
    for(uint i = 0; i < ts::node_child_count(self); ++i) {
        if(ts::node_child(self, i).type() == type) {
            return true;
        }
    }

    return false;
}

fn String TSNode.field_name(self) {
    TSNode parent = ts::node_parent(self);

    for(uint i = 0; i < ts::node_child_count(parent); ++i) {
        if(ts::node_eq(ts::node_child(parent, i),self)) {
            ZString field_name = ts::node_field_name_for_child(parent, i);
            return field_name == null ? "<NULL>" : field_name.str_view();
        }
    }

    unreachable();
}

fn bool TSNode.is_comment(self) {
    String node_type = self.type();

    return node_type == "line_comment" || node_type == "block_comment";
}

/*
    C3Fmt Helpers
*/

module c3fmt @private;
import ts;

fn void C3Fmt.append_char(&self, char c) {
    self.line_buffer.text.append_char(c);

    if(c == '\n') {
        self.flush_line();
    }
}

fn void C3Fmt.append_str(&self, String str) {
    foreach(char c : str) {
        self.append_char(c);
    }
}

fn void C3Fmt.append_node_str(&self, TSNode node) {
    self.append_str(node.get_text(self.source_code));
}

fn void C3Fmt.white_space(&self) {
    self.append_char(' ');
}

fn void C3Fmt.newline(&self) {
    self.append_char('\n');
}

fn void C3Fmt.insert_wrap_point(&self, WrapPointKind kind) {
    self.line_buffer.wrap_points.push({ .where = (uint)self.line_buffer.text.len(), .kind = kind });
}

fn uint C3Fmt.length_in_document(&self, String str) {
    uint count = 0;
    foreach(char c : str) {
        switch(c) {
            case '\n':
                break;
            case '\t':
                count += self.config.tab_size;

            default:
                count += 1;
        }
    }

    return count;
}

import std::io;

fn void C3Fmt.flush_line(&self, bool write_newline = true) => @pool() {
    // Verify line is not empty / just line return
    String raw_trimmed = self.line_buffer.text.str_view().trim(" ");
    switch(raw_trimmed) {
        case "":
            self.reset_line_buffer();
            return;
        case "\n":
            self.reset_line_buffer();
            self.output_code.append("\n");
            return;
    }

    DString indent = dstring::temp();
    for(usz i = 0; i < self.context.indent_level; ++i) {
        if(self.config.use_tabs) {
            indent.append("\t");
        } else {
            for(usz j = 0; j < self.config.indent_width; ++j) {
                indent.append(" ");
            }
        }
    }

    uint total_len = self.length_in_document(indent.str_view()) +
        self.length_in_document(self.line_buffer.text.str_view());

    // Wrap line
    if(self.config.max_line_length > 0 && total_len > self.config.max_line_length) {
        bool has_arg_wp = false;
        foreach(WrapPoint wp : self.line_buffer.wrap_points) {
            if(wp.kind == ARG) {
                has_arg_wp = true;
            }
        }

        usz azez = self.line_buffer.wrap_points.len();

        if(has_arg_wp) {
            DString line = self.line_buffer.text.copy(mem);
            defer line.free();
            usz offset = 0;

            foreach(WrapPoint wp : self.line_buffer.wrap_points) {
                if(wp.kind == ARG) {
                    line.insert_at(wp.where + offset, "\n");
                    offset += 1;
                    for(usz j = 0; j < self.config.indent_width; ++j) {
                        line.insert_at(wp.where + offset, " ");
                        offset += 1;
                    }
                }
                if(wp.kind == ARG_CLOSE_PAREN) {
                    line.insert_at(wp.where + offset, "\n");
                    offset += 1;

                    // TODO check if it was enough
                    // if it was not try to continue, there might be other wrap
                    // points after
                    break;
                }
            }

            self.reset_line_buffer();
            self.append_str(line.str_view());
            return;
        }
    }

    DString final = indent.tconcat(self.line_buffer.text);
    bool has_newline = final[final.len() - 1] == '\n';

    self.output_code.append(final.str_view().trim_right());
    if(has_newline) {
        self.output_code.append("\n");
    }

    self.reset_line_buffer();
}

fn void C3Fmt.reset_line_buffer (&self) {
    self.line_buffer.text.free();
    self.line_buffer.wrap_points.free();
    self.line_buffer.text.init(mem, 64);
    self.line_buffer.wrap_points.init(mem);
}

fn void C3Fmt.indent(&self) {
    self.context.indent_level++;
}

fn void C3Fmt.deindent(&self) {
    self.context.indent_level--;
}

fn bool String[].contains(&self, String str) {
    foreach(String token : self) {
        if(token == str) {
            return true;
        }
    }

    return false;
}