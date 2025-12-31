/* TODO-LIST: */
/*
doc_comment
ct_switch
wrapping
*/

/* KNOWN BUG */
/*
- Comment as last line of a case: clause (see l:59 switch_statements_f.c3)
- Comment following the colon of a case: clause
*/

module c3fmt;

import ts;
import tree_sitter_c3;

import c3fmt::printer;

struct C3Fmt
{
    Config  config;
    String  source_code;

    TokenBuffer buf;
    DString dstr_buf;
}

fn C3Fmt new(String source_code, Config config) {
    C3Fmt instance;

    instance.source_code = source_code.copy(mem);
    instance.config = config;
    instance.buf.init(mem);
    instance.dstr_buf.init(mem);

    return instance;
}

fn void C3Fmt.free(&self) {
    self.source_code.free(mem);
    self.buf.free();
    self.dstr_buf.free();
}

faultdef SOURCE_CODE_CONTAINS_ERROR;
faultdef CODE_SEMANTIC_MISMATCH;

fn void? C3Fmt.format(&self, bool check = false) {
    TSParser* parser = ts::parser::new_with_language(tree_sitter_c3::language())!;
	defer ts::parser_delete(parser);

    TSTree* tree = ts::parser::parse_string(parser, null, self.source_code);
    defer ts::tree_delete(tree);

    TSNode root = ts::tree_root_node(tree);
    if(ts::node_has_error(root)) {
        return SOURCE_CODE_CONTAINS_ERROR?;
    }

    self.process_node(root);
    self.buf.eof();

    self.print();

    if(check) {
        TSTree* f_tree = ts::parser::parse_string(parser, null, self.dstr_buf.str_view());
        defer ts::tree_delete(f_tree);

        TSNode f_root = ts::tree_root_node(f_tree);

        if(!ts::same_semantic(root, f_root)) {
            return CODE_SEMANTIC_MISMATCH?;
        }
    }
}

module c3fmt @private;

import std::io;
import ts;

<*
 Format a compound block" like node. Open and close with a specified string (that can contain line return(s)).
 Will then format each subchild. If a child is a "statement" it's its role to append a newline.
 This function will also preserve original blank lines between statements form source code. (can be capped)
 This function will preserve same line comments.

 @param node : "The processed node"
*>
fn void C3Fmt.process_compound(&self, TSNode node)
{
    for(uint i = 0; i < ts::node_named_child_count(node); ++i) {
        TSNode child = ts::node_named_child(node, i);

        int blank_line_amount = 0;
        if(i > 0) {
            TSNode sibling = ts::node_named_child(node, i - 1);
            blank_line_amount = child.start_point_row() - sibling.end_point_row();
        }
        blank_line_amount = min(blank_line_amount,
            self.config.max_blank_line_between_statements + 1);

        for(int j = 0; j < blank_line_amount - 1; ++j) {
            self.buf.newline();
        }

        if(child.is_comment() && blank_line_amount == 0 && i > 0) {
            if(self.buf.last()!!.kind == DEDENT) {
                // this is a lost commment after a case stmt
                assert(ts::node_named_child(node, i - 1).type() == "case_stmt"
                || ts::node_named_child(node, i - 1).type() == "default_stmt");

                Token dedent = self.buf.pop()!!; // gobble DEDENT
                assert(dedent.kind == DEDENT);
                assert(self.buf.gobble_last_newline());
                self.buf.space();
                self.process_node(child, true);
                self.buf.dedent(); // re-push dedent
                continue;
            }
            assert(self.buf.gobble_last_newline());
            self.buf.space();
        }

        self.process_node(child, true);
    }
}

<*
 Format a "line" composed of several nodes.
 Append a white space between each node.

 @param node : "The processed node"
 @param skip_space_type : "Do not append a white space before these type"
 @param skip_space_if_after : "Do not append a white space after these type"
 @param append_newline : "If true, will append a newline"
 @param wrap_point_before : "Will add a wrap point before the specified tokens"
 @param wrap_point_after : "Will add a wrap point after the specified tokens"
*>
fn void C3Fmt.process_composite(&self, TSNode node,
    String[] skip_space_type = { ";" },
    String[] skip_space_if_after = {},
    bool append_newline = false,
    String[] wrap_point_before = {},
    String[] wrap_point_after = {},
)
{
    for(uint i = 0; i < ts::node_child_count(node); ++i) {
        TSNode child = ts::node_child(node, i);
        String type = child.type();

        if(i > 0 &&
           !skip_space_type.contains(type) &&
           !skip_space_if_after.contains(ts::node_child(node, i - 1).type())
        )
        {
            self.buf.space();
        }

        if(wrap_point_before.contains(type)) {
            self.buf.wrap_point(BEFORE);
        }
        if(wrap_point_after.contains(type)) {
            self.buf.wrap_point(AFTER);
        }

        if(child.is_comment()) {
            if(child.type() == "block_comment") {
                self.process_block_comment(child);
            }
            if(child.type() == "line_comment") {
                // for instance:
                // if (aazeae) // THE COMMENT
                // { ... }
                // this force Allman brace style, it's very bad
                self.buf.text("/*");
                self.buf.space();
                String comment_content = child.get_text(self.source_code).strip("//").trim();
                self.buf.text(comment_content);
                self.buf.space();
                self.buf.text("*/");
            }
        } else {
            if(ts::node_is_named(child)) {
                self.process_node(child);
            } else {
                self.buf.text(child.get_text(self.source_code));
            }
        }
    }

    if(append_newline) {
        self.buf.newline();
    }
}

<*
 Rawly format node sequentially, without appending any separator between them.
 Useful for nodes like field accessor ("my_struct.my_field").

 @param node : "The processed node"
*>
fn void C3Fmt.process_sequence(&self, TSNode node) {
    for(uint i = 0; i < ts::node_child_count(node); ++i) {
        TSNode child = ts::node_child(node, i);

        if(child.is_comment()) {
            assert(child.type() == "block_comment");
            self.process_block_comment(child);
        } else {
            if(ts::node_is_named(child)) {
                self.process_node(child);
            } else {
                self.buf.text(child.get_text(self.source_code));
            }
        }
    }
}

<*
 A special function for case stmt, acts like a composite before encountering
 the colon, then switches to a compound-like behaviour.

 @param node : "The processed node"
*>
fn void C3Fmt.process_case_stmt(&self, TSNode node) {
    bool entered_stmt = false;
    uint colon_id = 0;

    for(uint i = 0; i < ts::node_child_count(node); ++i) {
        TSNode child = ts::node_child(node, i);

        if(!entered_stmt) {
            if(i > 0 && child.type() != ":") {
                self.buf.space();
            }

            if(child.is_comment()) {
                assert(child.type() == "block_comment");
                self.process_block_comment(child);
            } else {
                if(ts::node_is_named(child)) {
                    self.process_node(child);
                } else {
                    self.buf.text(child.get_text(self.source_code));
                }
            }

            if(child.type() == ":") {
                entered_stmt = true;
                colon_id = i;
                self.buf.newline();
                if(i == ts::node_child_count(node) - 1) {
                    return;
                }
                self.buf.indent();
            }
        } else {
            int blank_line_amount = 0;
            if(i > colon_id + 1) {
                TSNode sibling = ts::node_child(node, i - 1);
                blank_line_amount = child.start_point_row() - sibling.end_point_row();
            }
            blank_line_amount = min(blank_line_amount,
            self.config.max_blank_line_between_statements + 1);

            for(int j = 0; j < blank_line_amount - 1; ++j) {
                self.buf.newline();
            }

            if(child.is_comment() && blank_line_amount == 0 && i > colon_id + 1) {
                self.buf.gobble_last_newline();
                self.buf.space();
            }

            self.process_node(child);
        }
    }

    self.buf.dedent();
}

<*
 A special function for compile timecase stmt, acts like a composite
 before encountering the colon, then switches to a compound-like behaviour.

 @param node : "The processed node"
*>
fn void C3Fmt.process_ct_case_stmt(&self, TSNode node) {
    bool entered_stmt = false;
    uint colon_id = 0;

    for(uint i = 0; i < ts::node_child_count(node); ++i) {
        TSNode child = ts::node_child(node, i);

        if(!entered_stmt) {
            if(i > 0 && child.type() != ":") {
                self.buf.space();
            }

            if(child.is_comment()) {
                assert(child.type() == "block_comment");
                self.process_block_comment(child);
            } else {
                if(ts::node_is_named(child)) {
                    self.process_node(child);
                } else {
                    self.buf.text(child.get_text(self.source_code));
                }
            }

            if(child.type() == ":") {
                entered_stmt = true;
                colon_id = i;
                self.buf.newline();
                if(i == ts::node_child_count(node) - 1) {
                    return;
                }
                self.buf.indent();
            }
        } else {
            int blank_line_amount = 0;
            if(i > colon_id + 1) {
                TSNode sibling = ts::node_child(node, i - 1);
                blank_line_amount = child.start_point_row() - sibling.end_point_row();
            }
            blank_line_amount = min(blank_line_amount,
            self.config.max_blank_line_between_statements + 1);

            for(int j = 0; j < blank_line_amount - 1; ++j) {
                self.buf.newline();
            }

            if(child.is_comment() && blank_line_amount == 0 && i > colon_id + 1) {
                self.buf.gobble_last_newline();
                self.buf.space();
            }

            self.process_node(child);
        }
    }

    self.buf.dedent();
}

<*
 A special function for compile time switch stmt.

 @param node : "The processed node"
*>
fn void C3Fmt.process_ct_switch_stmt(&self, TSNode node) {
    bool entered_stmt = false;
    uint colon_id = 0;

    for(uint i = 0; i < ts::node_child_count(node); ++i) {
        TSNode child = ts::node_child(node, i);

        if(!entered_stmt) {
            if(i > 0 && child.type() != ":") {
                self.buf.space();
            }

            if(child.is_comment()) {
                // TODO
                //assert(child.type() == "block_comment");
                //self.process_block_comment(child);
            } else {
                if(ts::node_is_named(child)) {
                    self.process_node(child);
                } else {
                    self.buf.text(child.get_text(self.source_code));
                }
            }

            if(child.type() == ":") {
                entered_stmt = true;
                colon_id = i;
                self.buf.newline();
                self.buf.indent();
            }
        } else {
            int blank_line_amount = 0;
            if(i > colon_id + 1) {
                TSNode sibling = ts::node_child(node, i - 1);
                blank_line_amount = child.start_point_row() - sibling.end_point_row();
            }
            blank_line_amount = min(blank_line_amount,
            self.config.max_blank_line_between_statements + 1);

            for(int j = 0; j < blank_line_amount - 1; ++j) {
                self.buf.newline();
            }

            if(child.is_comment() && blank_line_amount == 0 && i > colon_id + 1) {
                TSNode sibling = ts::node_child(node, i - 1);
                // if the line finished and was a case_stmt
                // it will look like that in the buf
                // NEWLINE DEDENT
                if(sibling.type() == "ct_case_stmt") {
                    self.buf.pop()!!; // TODO handle the !!
                    self.buf.gobble_last_newline();
                    self.buf.space();

                    self.process_node(child);

                    self.buf.dedent();
                    continue;
                }
            }

            if(child.type() == "$endswitch") {
                assert(i == ts::node_child_count(node) - 1);
                self.buf.dedent();
                self.buf.text(child.get_text(self.source_code));
                self.buf.newline();
            } else {
                self.process_node(child);
            }
        }
    }
}

<*
 Pretty print a block comment.

 @param node : "The processed node"
*>
fn void C3Fmt.process_block_comment(&self, TSNode node) {
    TSNode content = ts::node_named_child(node, 0);
    self.buf.text("/*");
    self.buf.text(content.get_text(self.source_code));
    self.buf.text("*/");
}

<*
    Process a node of an unknown type
*>
fn void C3Fmt.process_node(&self, TSNode node, bool inside_compound = false) {
    switch (node.type())
    {
        /* ======================================== */
        /* TOP-LEVEL                                */
        /* ======================================== */
        case "source_file":
            self.process_compound(node);

        /* ======================================== */
        /* FUNCTIONS, MACROS & LAMBDAS              */
        /* ======================================== */
        case "func_declaration":
            self.process_composite(node,
                skip_space_type: { ";", "func_param_list" },
                append_newline: true
            );
        case "func_definition":
            self.process_composite(node,
                skip_space_type: { "func_param_list", "macro_func_body" },
                append_newline: true
            );
        case "func_header":
            self.process_composite(node,
                skip_space_type: { "." },
                skip_space_if_after: { "." },
            );
        case "func_param_list":
            self.process_composite(node,
                skip_space_type: { ")", "," },
                skip_space_if_after: { "(" },
                wrap_point_before: { "param", ")" },
            );
        case "param":
            self.process_composite(node,
                skip_space_if_after: { "&" },
            );
        case "param_default":
            self.process_composite(node);
        case "lambda_declaration":
            self.process_composite(node);
        case "macro_declaration":
            self.process_composite(node,
                skip_space_type: { "macro_param_list" }
            );
        case "macro_header":
            self.process_composite(node,
                skip_space_type: { "." },
                skip_space_if_after: { "." },
            );
        case "macro_param_list":
            self.process_composite(node,
                skip_space_type: { ")", ",", ";" },
                skip_space_if_after: { "(" },
                wrap_point_before: { "param", "trailing_block_param", ")" },
            );
        case "trailing_block_param":
            self.process_sequence(node);
        case "macro_func_body":
            TSNode child = ts::node_child(node, 0);
            switch(child.type()) {
                case "compound_stmt":
                    self.buf.newline();
                    self.buf.text("{");
                    self.buf.newline();
                    self.buf.indent();
                    self.process_compound(child);
                    self.buf.dedent();
                    self.buf.text("}");
                case "implies_body":
                    self.process_composite(node, append_newline: true);
                case "=>":
                    self.process_composite(node, append_newline: false);
            }
        case "implies_body":
            self.process_composite(node);
        case "=>":
            self.process_composite(node);

        /* ======================================== */
        /* DECLARATION                              */
        /* ======================================== */
        case "struct_declaration":
            self.process_composite(node, append_newline: true);
        case "struct_body":
            self.buf.newline();
            self.buf.text("{");
            self.buf.newline();
            self.buf.indent();
            self.process_compound(node);
            self.buf.dedent();
            self.buf.text("}");
        case "struct_member_declaration":
            self.process_composite(node, append_newline: true);
        case "enum_declaration":
            self.process_composite(node, append_newline: true);
        case "enum_spec":
            self.process_composite(node);
        case "enum_body":
            self.buf.newline();
            self.buf.text("{");
            self.buf.newline();
            self.buf.indent();
            self.process_compound(node);
            self.buf.dedent();
            self.buf.text("}");
        case "enum_constant":
            self.process_composite(node);

            bool has_comma = false;
            TSNode parent = ts::node_parent(node);
            bool start_searching;
            for(uint i = 0; i < ts::node_child_count(parent); ++i) {
                TSNode child = ts::node_child(parent, i);
                if(ts::node_eq(child, node)) {
                    start_searching = true;
                }
                if(start_searching) {
                    if(child.type() == ",") {
                        has_comma = true;
                        break;
                    }
                    if(child.type() == "}") {
                        break;
                    }
                }
            }

            if(has_comma) {
                self.buf.text(",");
            }

            self.buf.newline();
        case "enum_arg":
            self.process_composite(node);
        case "enum_param_list":
            self.process_composite(node,
                skip_space_type: { ",", ")" },
                skip_space_if_after: { "(" }
            );
        case "enum_param":
            self.process_composite(node);
        case "bitstruct_declaration":
            self.process_composite(node, append_newline: true);
        case "bitstruct_body":
            self.buf.newline();
            self.buf.text("{");
            self.buf.newline();
            self.buf.indent();
            self.process_compound(node);
            self.buf.dedent();
            self.buf.text("}");
        case "bitstruct_member_declaration":
            self.process_composite(node,
                skip_space_type: { "..", ";" },
                skip_space_if_after: { ".." },
                append_newline: true
            );
        case "interface_declaration": // TODO investigate the comma
            self.process_composite(node,
                skip_space_type: { "," },
                append_newline: true
            );
        case "interface_body":
            self.buf.newline();
            self.buf.text("{");
            self.buf.newline();
            self.buf.indent();
            self.process_compound(node);
            self.buf.dedent();
            self.buf.text("}");
        case "faultdef_declaration":
            self.process_composite(node,
                skip_space_type: { ",", ";" },
                append_newline: true
            );
        case "attrdef_declaration":
            self.process_composite(node,
                skip_space_type: { ";", "attribute_param_list" },
                append_newline: true
            );
        case "module_declaration":
            self.process_composite(node,
                skip_space_type: { ",", ";" },
                append_newline: true
            );
        case "import_declaration": // TODO is buggy (see https://github.com/c3lang/tree-sitter-c3/issues/49)
            self.process_composite(node,
                skip_space_type: { ",", ";" },
                append_newline: true
            );
        case "path_ident":
            self.process_sequence(node);
        case "module_resolution":
            self.process_sequence(node);
        case "path_type_ident":
            self.process_sequence(node);
        case "path_at_type_ident":
            self.process_sequence(node);
        case "typedef_declaration":
            self.process_composite(node,
                append_newline: true
            );
        case "alias_declaration":
            self.process_composite(node,
                append_newline: true
            );
        case "func_signature":
            self.process_composite(node,
                skip_space_type: { "func_param_list" }
            );
        case "var_declaration":
            self.process_composite(node);

        /* ======================================== */
        /* EXPRESSIONS                              */
        /* ======================================== */
        case "call_inline_attributes":
            self.process_composite(node);
        case "attributes":
            self.process_composite(node);
        case "attribute":
            self.process_sequence(node);
        case "attribute_arg_list":
            self.process_composite(node,
                skip_space_type: { ",", ")" },
                skip_space_if_after: { "(" },
            );
        case "attribute_arg":
            self.process_sequence(node);
        case "generic_type_ident":
            self.process_sequence(node);
        case "generic_arg_list":
            self.process_composite(node,
                skip_space_type: { ",", "}" },
                skip_space_if_after: { "{" },
            );
        case "access_ident":
            self.process_sequence(node);
        case "access_eval":
            self.process_sequence(node);
        case "flat_path":
            self.process_sequence(node);
        case "type":
            self.process_sequence(node);
        case "identifier_list":
            self.process_composite(node,
                skip_space_type: { "," }
            );
        case "attribute_list":
            self.process_composite(node,
                skip_space_type: { "," },
            );
        case "attribute_param_list":
            self.process_composite(node,
                skip_space_type: { ",", ")" },
                skip_space_if_after: { "(" },
            );
        case "paren_cond":
            self.process_composite(node,
                skip_space_type: { ")" },
                skip_space_if_after: { "(" },
            );
        case "try_unwrap":
            self.process_composite(node);
        case "catch_unwrap_list": // TODO not really sure what this is, i saw if(catch a, b) but ?
            self.process_composite(node,
                skip_space_type: { "," },
                skip_space_if_after: { "(" },
            );
        case "catch_unwrap":
            self.process_composite(node);
        case "call_expr":
            self.process_composite(node,
                skip_space_type: { "call_arg_list" }
            );
        case "call_arg_list":
            self.process_composite(node,
                skip_space_type: { ")", "," },
                skip_space_if_after: { "(" },
            );
        case "call_args":
            self.process_composite(node);
        case "call_arg":
            self.process_composite(node,
                skip_space_type: { ":", "range_expr", "[", "]" },
                skip_space_if_after: { "[", "..." },
            );
        case "ternary_expr":
            self.process_composite(node);
        case "elvis_orelse_expr":
            self.process_composite(node);
        case "binary_expr":
            self.process_composite(node);
        case "assignment_expr":
            self.process_composite(node);
        case "paren_expr":
            self.process_composite(node,
                skip_space_type: { ")" },
                skip_space_if_after: { "(" },
            );
        case "lambda_expr":
            self.process_composite(node);
        case "type_paren_expr":
            self.process_composite(node,
                skip_space_type: { ")" },
                skip_space_if_after: { "(" },
            );
        case "initializer_list":
            self.process_composite(node,
                skip_space_type: { "," },
            );
        case "comma_decl_or_expr":
            self.process_composite(node,
                skip_space_type: { ",", ")" },
                skip_space_if_after: { "(" }
            );
        case "interface_impl_list":
            self.process_composite(node,
                skip_space_type: { ",", ")" },
                skip_space_if_after: { "(" }
            );
        case "trailing_generic_expr":
            self.process_composite(node);
        case "generic_type_ident":
            self.process_composite(node);
        case "generic_arg_list":
            self.process_composite(node,
                    skip_space_type: { "}", "," },
                    skip_space_if_after: { "{" },
                );
        case "generic_param_list":
            self.process_composite(node,
                    skip_space_type: { "}", "," },
                    skip_space_if_after: { "{" },
                );
        case "initializer_element":
            self.process_composite(node);
        case "param_path": // TODO idk what this is, can we do { .x .y = 34 }??? why is
        // it a repeat(param_path_element)...
            self.process_composite(node);
        case "typed_initializer_list":
            self.process_composite(node,
                skip_space_type: { ")" },
                skip_space_if_after: { "(" },
            );
        case "param_path_element": // TO BE TESTED
        case "unary_expr":
        case "update_expr":
        case "optional_expr":
        case "cast_expr":
        case "field_expr":
        case "subscript_expr":
        case "range_expr":
        case "rethrow_expr": // TO BE TESTED
        case "type_access_expr":
            self.process_sequence(node);


        /* ======================================== */
        /* STATEMENTS & CONTROL FLOW                */
        /* ======================================== */
        case "compound_stmt":
            if(!inside_compound) {
                // shitty workaround to handle compound stmt
                // for scope decl
                self.buf.newline();
            }

            self.buf.text("{");
            self.buf.newline();
            self.buf.indent();
            self.process_compound(node);
            self.buf.dedent();
            self.buf.text("}");

            if(inside_compound) {
                self.buf.newline();
            }
        case "var_stmt":
            self.process_composite(node, append_newline: true);
        case "expr_stmt":
            self.process_composite(node,
                skip_space_type: { ";", ",", ")", "(" },
                skip_space_if_after: { "(" },
                append_newline: true
            );
        case "defer_stmt":
            self.process_composite(node, append_newline: true);
        case "defer_catch_ident":
            self.process_composite(node,
                skip_space_type: { ")" },
                skip_space_if_after: { "(" },
                append_newline: true
            );
        case "return_stmt":
            self.process_composite(node, append_newline: true);
        case "break_stmt":
            self.process_composite(node, append_newline: true);
        case "nextcase_stmt":
            self.process_composite(node,
                skip_space_type: { ";", ":" },
                append_newline: true
            );
        case "continue_stmt":
            self.process_composite(node, append_newline: true);
        case "assert_stmt":
            self.process_composite(node,
                skip_space_type: { ";", ")" },
                skip_space_if_after: { "(" },
                append_newline: true
            );
        case "for_stmt":
            TSNode body = node.get_child_with_field("body");
            self.process_composite(node,
                append_newline:
                    body.type() == "compound_stmt" ||
                    body.type() == ";"
            // TODO investigate this (see io/formatter_private.c3:363)
            );
        case "for_cond":
            self.process_composite(node,
                skip_space_type: { ";", ")" },
                skip_space_if_after: { "(" },
            );
        case "foreach_stmt":
            TSNode body = node.get_child_with_field("body");
            self.process_composite(node, append_newline: body.type() == "compound_stmt");
        case "foreach_cond":
            self.process_composite(node,
                skip_space_type: { ",", ")" },
                skip_space_if_after: { "(" },
            );
        case "foreach_var":
            self.process_composite(node,
                skip_space_if_after: { "&" },
            );
        case "while_stmt":
            TSNode body = node.get_child_with_field("body");
            self.process_composite(node, append_newline: body.type() == "compound_stmt");
        case "do_stmt":
            self.process_composite(node, append_newline: true);
        case "if_stmt":
            TSNode body = node.get_child_with_field("body");
            TSNode parent = ts::node_parent(node);
            self.process_composite(node,
                append_newline: body.type() == "compound_stmt" &&
                                parent.type() != "else_part"
            );
        case "else_part":
            if(self.config.else_on_new_line) {
                self.buf.newline();
            }
            self.process_composite(node);
        case "switch_stmt":
            self.process_composite(node,
                skip_space_type: { "switch_body" },
                append_newline: true
            );
        case "switch_body":
            self.buf.newline();
            self.buf.text("{");
            self.buf.newline();
            self.buf.indent();
            self.process_compound(node);
            self.buf.dedent();
            self.buf.text("}");
        case "case_stmt":
            self.process_case_stmt(node);
        case "default_stmt": // idem
            self.process_case_stmt(node);
        case "case_range":
            self.process_sequence(node);
        case "asm_block_stmt": // TODO
            self.buf.text(node.get_text(self.source_code));
            self.buf.newline();
        case "ct_assert_stmt":
            self.process_composite(node,
                skip_space_type: { ";", ")", "," },
                skip_space_if_after: { "(" },
                append_newline: true
            );
        case "ct_echo_stmt":
            self.process_composite(node, append_newline: true);
        case "ct_include_stmt":
            self.process_composite(node, append_newline: true);
        case "ct_exec_stmt":
            self.process_composite(node,
                skip_space_type: { ";", ")", "," },
                skip_space_if_after: { "(" },
                append_newline: true
            );
        case "ct_stmt_body":
            self.buf.newline();
            self.buf.indent();
            self.process_compound(node);
            self.buf.dedent();
        case "ct_if_stmt":
            self.process_composite(node,
                skip_space_type: { "ct_else_stmt", "ct_stmt_body", "$endif" },
                append_newline: true
            );
        case "ct_if_cond":
            self.process_sequence(node);
        case "ct_else_stmt":
            self.process_composite(node,
                skip_space_type: { "ct_else_stmt", "ct_stmt_body", "$endif" },
            );
        case "ct_for_stmt":
            self.process_composite(node,
                skip_space_type: { ":", "ct_stmt_body", "$endfor" },
                append_newline: true
            );
        case "ct_for_cond":
            self.process_composite(node);
        case "ct_foreach_stmt":
            self.process_composite(node,
                skip_space_type: { ":", "ct_stmt_body", "$endforeach" },
                append_newline: true
            );
        case "ct_foreach_cond":
            self.process_composite(node,
                skip_space_type: { "," },
            );
        case "ct_switch_stmt":
            self.process_ct_switch_stmt(node); // TODO comment after :
        case "ct_switch_cond":
            self.buf.text(node.get_text(self.source_code)); // TODO
        case "ct_case_stmt":
            self.process_composite(node,
                skip_space_type: { ":" }
            ); // TODO this works but performs some unnecessary steps

        /* ======================================== */
        /* COMMENTS                                 */
        /* ======================================== */
        case "block_comment":
            self.process_block_comment(node);
            self.buf.newline();
        case "line_comment":
            self.buf.text(node.get_text(self.source_code));
            self.buf.newline();
        case "doc_comment": // TODO not urgent
            self.buf.text(node.get_text(self.source_code));
            self.buf.newline();

        /* ======================================== */
        /* COMMON LEAVES                            */
        /* ======================================== */
        case "ident":
        case "ident_expr":
        case "ct_ident":
        case "at_ident":
        case "hash_ident":
        case "const_ident":
        case "ct_const_ident":
        case "type_ident":
        case "type_suffix":
        case "base_type_name":
        case "ct_type_ident":
        case "at_type_ident":
        case "builtin":
        case "builtin_const":
        case "integer_literal":
        case "real_literal":
        case "char_literal":
        case "string_literal":
        case "raw_string_literal":
        case "byte_literal":
        case "bytes_literal":
        case "label":
        case "label_target":
        case "true":
        case "false":
        case "null":
        case "default": // maybe not necesarry idk waiting for switch support.
        case "base_type_name":
        case "overload_operator":
            self.buf.text(node.get_text(self.source_code));

        case "bytes_expr": // TODO idk what this is, a space separated list of bytes_literal ?
        case "string_expr": // same...
            self.process_composite(node);

        // Known for not working, waiting for https://github.com/c3lang/tree-sitter-c3/issues/50
        case "const_declaration":
        case "declaration":
            self.process_composite(node);
        case "declaration_stmt":
        case "global_declaration":
            self.process_composite(node,
                append_newline: true
            );

        default:
            io::eprintfn("Type %s is not supported by c3fmt (yet!).", node.type());
            self.buf.text(node.get_text(self.source_code));
            self.buf.newline();
            //unreachable();
    }
}