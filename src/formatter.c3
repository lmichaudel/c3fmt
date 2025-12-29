/* TODOLIST:

doc_comment

// NOTE: Waiting for #50 in treesitter-c3
global_declaration
declaration
declaration_stmt

switch
ct_switch

wrapping
*/

/* KNOWN BUG
    - Multiline comment (see the asm_block one)
    - Comment as last line of a case: clause
    - Comment following the colon of a case: clause
    - I hate case:
*/
module c3fmt;

import std::io;
import std::collections;

import ts;
import tree_sitter_c3;

struct Context {
    uint indent_level;
}

enum WrapPointKind {
    ARG,
    ARG_CLOSE_PAREN,
    EQUAL,
    FOR_COND
}

struct WrapPoint {
    uint where;
    WrapPointKind kind;
}
struct LineBuffer {
    DString text;
    List{WrapPoint} wrap_points;
}

struct C3Fmt
{
    Config  config;

    Context context;
    String  source_code;

    DString output_code;
    LineBuffer line_buffer;

    bool wrapping_allowed;
}

fn C3Fmt new(Allocator allocator, String source_code, Config config) {
    C3Fmt instance;

    instance.source_code = source_code.copy(allocator);
    instance.config = config;
    instance.output_code = dstring::new(allocator);
    instance.wrapping_allowed = true;

    return instance;
}

faultdef TREE_SITTER_ERROR;
faultdef SOURCE_CODE_CONTAIN_ERROR;

fn void? C3Fmt.format(&self) {
    TSParser*? parser = ts::parser::new_with_language(tree_sitter_c3::language());
	defer (void)ts::parser_delete(parser);
	if (catch excuse = parser) {
		return TREE_SITTER_ERROR?;
	}

    TSTree*? tree = ts::parser::parse_string(parser, null, self.source_code);
    defer (void)ts::tree_delete(tree);
    if (catch excuse = tree) {
		return TREE_SITTER_ERROR?;
    }

    TSNode root = ts::tree_root_node(tree);

    if(ts::node_has_error(root)) {
        return SOURCE_CODE_CONTAIN_ERROR?;
    }

    self.line_buffer.text.init(mem, 64);
    self.line_buffer.wrap_points.init(mem);

    self.process_node(root);
    self.flush_line();

    while(self.output_code[self.output_code.len() - 1] == '\n') {
        self.output_code.chop(self.output_code.len() - 1);
    }

    self.line_buffer.text.free();
    self.line_buffer.wrap_points.free();
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
 @param opening_delimiter : "A string to be appended before processing"
 @param closing_delimiter : "A string to be appended after processing"
 @param increase_indent : "If true, each children will be formatted one indent level up"
*>
fn void C3Fmt.process_compound
(
    &self, TSNode node,
    String opening_delimiter = "",
    String closing_delimiter = "",
    bool increase_indent = false
)
{
    self.append_str(opening_delimiter);

    if(increase_indent) {
        self.indent();
    }

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
            self.newline();
        }

        // TODO Same line comment
        if(child.is_comment() && blank_line_amount == 0) {
            //self.white_space();
        }

        self.process_node(child);
    }

    if(increase_indent) {
        self.deindent();
    }

    self.append_str(closing_delimiter);
}

<*
 Format a "line" composed of several nodes. Append a white space between each node.

 @param node : "The processed node"
 @param skip_space_type : "Do not append a white space before these type"
 @param skip_space_if_after : "Do not append a white space after these type"
*>
fn void C3Fmt.process_composite(&self, TSNode node,
    String[] skip_space_type = { ";" },
    String[] skip_space_if_after = {},
    bool append_newline = false
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
            self.white_space();
        }

        // WRAP POINTS (EXPERIMENTAL)
        if((node.type() == "call_arg_list" && child.type() == "call_arg") ||
           (node.type() == "func_param_list" && child.type() == "param")
        )
        {
            self.insert_wrap_point(ARG);
        }
        if((node.type() == "call_arg_list" && i == ts::node_child_count(node) - 1) ||
           (node.type() == "func_param_list" && i == ts::node_child_count(node) - 1)
        )
        {
            assert(child.type() == ")");
            self.insert_wrap_point(ARG_CLOSE_PAREN);
        }

        if(child.is_comment()) {
            // if (!same_line) gobble space (rare)
            self.append_node_str(child);
            self.newline();
            // TODO
            continue;
        }

        if(ts::node_is_named(child)) {
            self.process_node(child);
        } else {
            self.append_node_str(child);
        }
    }

    if(append_newline) {
        self.newline();
    }
}

<*
 Rawly format node sequentially, without appending any separator between them.
 Useful for nodes like field accessor ("my_struct.my_field")

 @param node : "The processed node"
*>
fn void C3Fmt.process_sequence(&self, TSNode node) {
    for(uint i = 0; i < ts::node_child_count(node); ++i) {
        TSNode child = ts::node_child(node, i);

        if(ts::node_is_named(child)) {
            self.process_node(child);
        } else {
            self.append_node_str(child);
        }
    }
}

fn void C3Fmt.process_case_stmt(&self, TSNode node) {
    bool entered_stmt = false;
    uint colon_id = 0;

    for(uint i = 0; i < ts::node_child_count(node); ++i) {
        TSNode child = ts::node_child(node, i);

        if(!entered_stmt) {
            if(i > 0 && child.type() != ":") {
                self.white_space();
            }

            if(child.is_comment()) {
                self.append_node_str(child);
                continue;
            }

            if(ts::node_is_named(child)) {
                self.process_node(child);
            } else {
                self.append_node_str(child);
            }

            if(child.type() == ":") {
                entered_stmt = true;
                colon_id = i;
                self.newline();
                self.indent();
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
                self.newline();
            }

            if(child.is_comment() && blank_line_amount == 0) {
                // TODO
                //self.white_space();
            }

            self.process_node(child);
        }
    }

    self.deindent();
}

<*
    Process a node of an unknown type
*>
fn void C3Fmt.process_node(&self, TSNode node) {
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
                skip_space_type: { "func_param_list" },
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
            self.process_composite(node);
        case "macro_header":
        case "macro_param_list":
            self.append_node_str(node); // TODO
        case "macro_func_body":
            TSNode child = ts::node_child(node, 0);
            switch(child.type()) {
                case "compound_stmt":
                    self.process_compound(child,
                        opening_delimiter: "\n{\n",
                        closing_delimiter: "}",
                        increase_indent: true
                    );
                case "implies_body":
                case "=>":
                    self.wrapping_allowed = false;
                    self.process_composite(node, append_newline: false);
                    self.wrapping_allowed = true;
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
            String opening = self.config.brace_style == ALLMAN ? "\n{\n" : "{\n";
            self.process_compound(node,
                opening_delimiter: opening,
                closing_delimiter: "}",
                increase_indent: true
            );
        case "struct_member_declaration":
            self.process_composite(node, append_newline: true);
        case "enum_declaration":
            self.process_composite(node, append_newline: true);
        case "enum_spec":
            self.process_composite(node);
        case "enum_body":
            String opening = self.config.brace_style == ALLMAN ? "\n{\n" : "{\n";
            self.process_compound(node,
                opening_delimiter: opening,
                closing_delimiter: "}",
                increase_indent: true
            );
        case "enum_constant":
            self.process_composite(node);
            self.append_str(",\n"); // TODO
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
            String opening = self.config.brace_style == ALLMAN ? "\n{\n" : "{\n";
            self.process_compound(node,
                opening_delimiter: opening,
                closing_delimiter: "}",
                increase_indent: true
            );
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
            String opening = self.config.brace_style == ALLMAN ? "\n{\n" : "{\n";
            self.process_compound(node,
                opening_delimiter: opening,
                closing_delimiter: "}",
                increase_indent: true
            );
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
        case "path_ident": // TODO
        case "path_type_ident": // TODO
            self.append_node_str(node);
        case "typedef_declaration":
            self.process_composite(node,
                append_newline: true
            );
        case "alias_declaration": // TO BE TESTED
            self.process_composite(node,
                append_newline: true
            );
        case "func_signature":
            self.process_composite(node);
        case "var_declaration":
            self.process_composite(node);

        /* ======================================== */
        /* EXPRESSIONS                              */
        /* ======================================== */
        case "call_inline_attributes": // TODO what's the difference with "attributes" anyway ?
        case "attributes":
            self.process_composite(node);
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
            self.append_node_str(node); // TODO
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
        case "initializer_list": // TO BE TESTED
            self.process_composite(node,
                skip_space_type: { "," },
            );
        case "comma_decl_or_expr": // TO BE TESTED
            self.process_composite(node,
                skip_space_type: { ",", ")" },
                skip_space_if_after: { "(" }
            );
        case "interface_impl_list": // TO BE TESTED
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
        case "initializer_element": // TO BE TESTED
            self.process_composite(node);
        case "param_path": // idk what this is, can we do { .x .y = 34 }??? why is
        // it a repeat(param_path_element)...
            self.process_composite(node);
        case "param_path_element": // TO BE TESTED
        case "typed_initializer_list": // TO BE TESTED
        case "unary_expr":
        case "update_expr":
        case "optional_expr":
        case "cast_expr": // TO BE TESTED + configure it
        case "field_expr": // TO BE TESTED
        case "subscript_expr": // TO BE TESTED
        case "range_expr": // TO BE TESTED + maybe have space between .. or : ?
        case "rethrow_expr": // TO BE TESTED
        case "type_access_expr":
            self.process_sequence(node);


        /* ======================================== */
        /* STATEMENTS & CONTROL FLOW                */
        /* ======================================== */
        case "compound_stmt":
            String opening = self.config.brace_style == ALLMAN ? "\n{\n" : "{\n";
            self.process_compound(node,
                opening_delimiter: opening,
                closing_delimiter: "}",
                increase_indent: true
            );
        case "var_stmt":
            self.process_composite(node, append_newline: true);
        case "expr_stmt":
            self.process_composite(node,
                skip_space_type: { ";", ",", ")" },
                skip_space_if_after: { "(" },
                append_newline: true
            );
        case "defer_stmt":
            self.process_composite(node);
        case "defer_catch_ident":
            self.process_composite(node,
                skip_space_type: { ")" },
                skip_space_if_after: { "(" }
            );
        case "return_stmt":
            self.process_composite(node, append_newline: true);
        case "break_stmt":
            self.process_composite(node, append_newline: true);
        case "nextcase_stmt": // TO BE TESTED
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
            self.process_composite(node, append_newline: body.type() == "compound_stmt");
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
                self.newline();
            }
            self.process_composite(node);
        case "switch_stmt":
            self.process_composite(node, append_newline: true);
        case "switch_body":
            String opening = self.config.brace_style == ALLMAN ? "\n{\n" : "{\n";
            self.process_compound(node,
                opening_delimiter: opening,
                closing_delimiter: "}",
                increase_indent: true
            );
        case "case_stmt": // TODO, this one will be a pain and will surely need its own work
            self.process_case_stmt(node);
        case "default_stmt": // idem
            self.process_case_stmt(node);
        case "case_range": // TODO
            self.append_node_str(node);
        case "asm_block_stmt": // TODO
            self.append_node_str(node);
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
            self.process_compound(node,
                opening_delimiter: "\n",
                closing_delimiter: "",
                increase_indent: true
            );
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
            self.append_node_str(node); // TODO, need special handling...
            self.newline();
        /* todo

        asm_stmt
        */

        /* ======================================== */
        /* COMMENTS                                 */
        /* ======================================== */
        case "block_comment": // BUG multiline block
            self.append_node_str(node);
            self.newline();
        case "line_comment":
            self.append_node_str(node);
            self.newline();
        case "doc_comment": // TODO not urgent
            self.append_node_str(node);
            self.newline();

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
        case "attribute": // TODO (parenthesis after)
        case "generic_type_ident": // TO BE TESTED / TODO
        case "access_ident": // TODO idk
        case "base_type_name":
        case "flat_path": // TODO don't really know what this is
            self.append_node_str(node);

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
            self.append_node_str(node);
            //unreachable();
    }
}