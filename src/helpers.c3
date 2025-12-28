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
    if(c == '\n') {
        self.flush_line();
    } else {
        self.line_buffer.text.append_char(c);
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

fn void C3Fmt.flush_line(&self, bool write_newline = true) => @pool() {
    DString indented;
    indented.tinit(64);

    if(self.line_buffer.text.str_view() != "") { // avoid outputting empty line with spaces
        for(usz i = 0; i < self.context.indent_level; ++i) {
            if(self.config.use_tabs) {
                indented.append("\t");
            } else {
                for(usz j = 0; j < self.config.indent_width; ++j) {
                    indented.append(" ");
                }
            }
        }
    }

    DString final = indented.tconcat(self.line_buffer.text);

    // Trim
    while(final.len() != 0
        && (final[final.len() - 1] == ' ' || final[final.len() - 1] == '\t'))
    {
        final.chop(final.len() - 1);
    }

    self.output_code.append(final);
    if(write_newline) {
        self.output_code.append_char('\n');
    }

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