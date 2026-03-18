module c3fmt;

import ts;
import tree_sitter_c3;

import c3fmt::printer;
import c3fmt::token;

struct C3Fmt
{
	Config config;
	String source_code;

	bool wrapping_enabled;
	bool formatter_enabled;

	usz next_group_id;

	TSParser* parser;
	TokenBuffer buf;
	DString dstr_buf;
	uint indent_level;
}

fn C3Fmt? new(String source_code, Config config)
{
	C3Fmt instance;

	instance.source_code = source_code.copy(mem);
	instance.config = config;
	instance.wrapping_enabled = true;
	instance.formatter_enabled = true;
	instance.parser = ts::parser::new_with_language(tree_sitter_c3::language())!;
	instance.buf.init(mem);
	instance.dstr_buf.init(mem);
	instance.indent_level = 0;

	return instance;
}

fn void C3Fmt.free(&self)
{
	ts::parser_delete(self.parser);
	self.source_code.free(mem);
	self.buf.free();
	self.dstr_buf.free();
}

fn usz C3Fmt.begin_wrap_group(&self, usz priority)
{
	self.next_group_id++;
	self.buf.push(token::begin_wrap_group(self.next_group_id, priority));
	return self.next_group_id;
}

fn void C3Fmt.indent(&self)
{
	self.indent_level++;
	self.buf.push(token::indent());
}

fn void C3Fmt.dedent(&self)
{
	if (self.indent_level > 0)
	{
		self.indent_level--;
		self.buf.push(token::dedent());
	}
}

fn Token? C3Fmt.pop_token(&self)
{
	Token? tok = self.buf.pop();
	if (try t = tok)
	{
		if (t.kind == TokenKind.INDENT)
		{
			self.indent_level--;
		}
		else if (t.kind == TokenKind.DEDENT)
		{
			self.indent_level++;
		}
	}
	return tok;
}

fn usz C3Fmt.current_column(&self)
{
	usz col = (usz)self.indent_level * (self.config.use_tabs ? self.config.tab_size : self.config.indent_width);

	// Scan backwards for current line tokens
	int i = (int)self.buf.len() - 1;
	while (i >= 0 && self.buf[i].kind != NEWLINE)
	{
		if (self.buf[i].kind == ALIGN)
		{
			if (self.buf[i].align_col > col)
			{
				col = self.buf[i].align_col;
			}
		}
		else
		{
			col += self.buf[i].len();
		}
		i--;
	}
	return col;
}

faultdef SOURCE_CODE_CONTAINS_ERROR;
faultdef CODE_SEMANTIC_MISMATCH;

fn void? C3Fmt.format(&self, bool check = false)
{
	ts::parser_reset(self.parser);

	TSTree* tree = ts::parser::parse_string(self.parser, null, self.source_code);
	defer ts::tree_delete(tree);

	TSNode root = ts::tree_root_node(tree);
	if (ts::node_has_error(root))
	{
		return SOURCE_CODE_CONTAINS_ERROR~;
	}

	self.process_node(root);
	self.buf.eof();

	self.print();

	if (check)
	{
		ts::parser_reset(self.parser);
		TSTree* f_tree = ts::parser::parse_string(
			self.parser,
			null,
			self.dstr_buf.str_view()
		);
		defer ts::tree_delete(f_tree);

		TSNode f_root = ts::tree_root_node(f_tree);

		if (!ts::same_semantic(root, f_root))
		{
			return CODE_SEMANTIC_MISMATCH~;
		}
	}
}

module c3fmt @private;

import std::io;
import ts;

<*
 Reattach a comment node to the previous statement when it appears immediately
 after it (blank_line_amount == 0, trailing) or one line below a scope-exit
 token (blank_line_amount == 1, restick).

 Returns true if the comment was reattached and the caller's loop should
 continue to the next child.

 @param child            : "The comment node to reattach."
 @param blank_line_amount : "Blank lines between the previous sibling and this node."
 @param with_repair_indent : "When true, first pop() the last token and handle the case where it is an INDENT token (compound/asm variant). When false, simply gobble the last newline (uncanny-scope variant)."
*>
fn bool C3Fmt.reattach_comment(&self, TSNode child, int blank_line_amount, bool with_repair_indent = true)
{
	if (!(blank_line_amount == 0 || blank_line_amount == 1)) return false;
	if (!child.is_comment()) return false;

	bool popped_indent = false;
	if (try last = self.buf.last())
	{
		if (last.kind == TokenKind.DEDENT)
		{
			(void)self.pop_token();
			popped_indent = true;
		}
	}

	if (blank_line_amount == 0) // trailing
	{
		if (with_repair_indent)
		{
			bool repair_indent = false;
			if (self.buf.len() == 0)
			{
				if (popped_indent) self.dedent();
				return false;
			}
			Token tok = self.pop_token()!!;

			if (tok.kind == TokenKind.INDENT)
			{
				if (!self.buf.gobble_last_newline())
				{
					self.buf.push(tok);
					self.indent_level++;
					if (popped_indent) self.dedent();
					return false;
				}
				repair_indent = true;
			}
			else if (tok.kind == TokenKind.NEWLINE)
			{
				// fine
			}
			else
			{
				self.buf.push(tok);
				if (popped_indent) self.dedent();
				return false;
			}

			self.buf.space();
			self.process_comment(child);
			self.buf.newline();

			if (repair_indent)
			{
				self.indent();
			}
		}
		else
		{
			if (self.buf.len() == 0 || !self.buf.gobble_last_newline())
			{
				if (popped_indent) self.dedent();
				return false;
			}
			self.buf.space();
			self.process_comment(child);
			self.buf.newline();
		}

		if (popped_indent)
		{
			self.dedent();
		}
		return true;
	}

	if (blank_line_amount == 1
		&& popped_indent) // restick to previous uncanny stmt
	{
		self.process_comment(child);
		self.buf.newline();
		self.dedent();
		return true;
	}

	if (popped_indent)
	{
		self.dedent(); // Revert
	}

	return false;
}

faultdef NOT_FOUND;

fn bool C3Fmt.has_trailing_comma(&self, TSNode node)
{
	TSNode parent = ts::node_parent(node);
	if (ts::node_is_null(parent)) return false;

	bool start_searching = false;
	for (uint i = 0; i < ts::node_child_count(parent); ++i)
	{
		TSNode child = ts::node_child(parent, i);
		if (ts::node_eq(child, node))
		{
			start_searching = true;
			continue;
		}
		if (start_searching)
		{
			if (child.type() == ",") return true;
			if (ts::node_is_named(child) || child.type() == "}" || child.type() == "{") return false;
		}
	}
	return false;
}

fn bool is_alignable_block_node(TSNode node)
{
	String type = node.type();
	if (type == "declaration_stmt" || type == "global_declaration")
	{
		if (ts::node_named_child_count(node) == 0) return false;
		TSNode inner = ts::node_named_child(node, 0);
		String inner_type = inner.type();
		return inner_type == "const_declaration" || inner_type == "var_declaration";
	}
	return type == "const_declaration" || type == "var_declaration" || type == "macro_declaration" || type == "enum_constant";
}

fn TSNode find_assignment_op(TSNode node)
{
	TSNode target = node;
	String type = node.type();
	if (type == "declaration_stmt" || type == "global_declaration")
	{
		if (ts::node_named_child_count(node) == 0) return (TSNode){};
		target = ts::node_named_child(node, 0);
	}

	for (uint i = 0; i < ts::node_child_count(target); ++i)
	{
		TSNode c = ts::node_child(target, i);
		String t = c.type();
		if (t == "=" || t == "=>") return c;
		if ((t == "initializer_list" || t == "enum_arg") && type == "enum_constant") return c;
		if (t == "macro_func_body")
		{
			if (c.has_child_of_type("implies_body")) return c;
		}
	}
	return (TSNode){};
}

fn void C3Fmt.process_assignment_left(&self, TSNode target, TSNode op)
{
	bool first = true;
	for (uint k = 0; k < ts::node_child_count(target); ++k) {
		TSNode c = ts::node_child(target, k);
		if (ts::node_eq(c, op)) break;
		if (ts::node_is_named(c)) {
			if (!first && c.type() != "macro_param_list") self.buf.push(token::space());
			self.process_node(c);
			first = false;
		} else {
			String t = c.get_text(self.source_code);
			if (t == "const" || t == "var" || t == "static" || t == "pub" || t == "macro") {
				if (!first) self.buf.push(token::space());
				self.buf.push(token::text(t));
				first = false;
			}
		}
	}
}

fn void C3Fmt.process_aligned_block(&self, TSNode parent, uint start_index, uint end_index)
{
	usz max_op_col = 0;
	usz max_comment_col = 0;

	uint named_child_count = ts::node_named_child_count(parent);

	// dry run to find columns
	for (uint i = start_index; i < end_index; ++i)
	{
		TSNode child = ts::node_named_child(parent, i);
		if (child.is_comment()) continue;

		usz start_buf_len = self.buf.len();

		TSNode op = find_assignment_op(child);
		if (!ts::node_is_null(op))
		{
			// Format up to the '='
			TSNode target = (child.type() == "declaration_stmt" || child.type() == "global_declaration") ? ts::node_named_child(child, 0) : child;
			self.process_assignment_left(target, op);
			max_op_col = max(max_op_col, self.current_column());
		}

		// Reset and format whole node without trailing newline to find comment col
		while (self.buf.len() > start_buf_len) (void)self.pop_token();

		if (child.type() == "declaration_stmt" || child.type() == "global_declaration")
		{
			// We need to NOT append newline here
			self.process_composite(child, append_newline: false);
		}
		else
		{
			self.process_node(child, false);
		}

		if (i + 1 < named_child_count)
		{
			TSNode next = ts::node_named_child(parent, i + 1);
			if (next.start_point_row() == child.end_point_row() && next.is_comment())
			{
				max_comment_col = max(max_comment_col, self.current_column());
			}
		}

		while (self.buf.len() > start_buf_len) {
			(void)self.pop_token();
		}
	}

	if (max_op_col > 80) {
		max_op_col = 0;
	}


	// Final pass
	uint i = start_index;
	while (i < end_index)
	{
		TSNode child = ts::node_named_child(parent, i);

		int blank_line_amount = 0;
		if (i > start_index)
		{
			TSNode sibling = ts::node_named_child(parent, i - 1);
			blank_line_amount = (int)child.start_point_row() - (int)sibling.end_point_row();
			for (int j = 0; j < blank_line_amount - 1; ++j) self.buf.push(token::newline());
		}

		TSNode op = find_assignment_op(child);
		if (!ts::node_is_null(op) && max_op_col > 0)
		{
			TSNode target = (child.type() == "declaration_stmt" || child.type() == "global_declaration") ? ts::node_named_child(child, 0) : child;
			TSNode right = (target.type() == "macro_declaration" || !target.has_child_with_field("right")) ? (TSNode){} : target.get_child_with_field("right");

			// Format until '='
			self.process_assignment_left(target, op);

			self.buf.push(token::align(max_op_col));
			self.buf.push(token::space());

			if (!ts::node_is_null(right))
			{
				self.buf.push(token::text(op.get_text(self.source_code)));
				self.buf.push(token::space());
			}

			TSNode right_to_use = ts::node_is_null(right) ? op : right;

			// Value alignment logic for math signs
			if (!ts::node_is_null(right_to_use)) {
				String text = right_to_use.get_text(self.source_code);
				bool has_negatives = false;
				for (uint m = start_index; m < end_index; ++m) {
					TSNode decl = ts::node_named_child(parent, m);
					TSNode op2 = find_assignment_op(decl);
					if (!ts::node_is_null(op2)) {
						TSNode t2 = (decl.type() == "declaration_stmt" || decl.type() == "global_declaration") ? ts::node_named_child(decl, 0) : decl;
						TSNode r2 = (t2.type() == "macro_declaration" || !t2.has_child_with_field("right")) ? (TSNode){} : t2.get_child_with_field("right");
						// For macros, the 'right' side is the body, but it starts with =>
						if (ts::node_is_null(r2) && t2.type() == "macro_declaration") r2 = op2;

						if (!ts::node_is_null(r2) && r2.get_text(self.source_code).starts_with("-")) {
							has_negatives = true;
							break;
						}
					}
				}
				if (has_negatives && !text.starts_with("-")) {
					self.buf.push(token::space());
				}
				self.process_node(right_to_use);
			}

			// Format rest (normally just ';')
			bool found_op = false;
			for (uint k = 0; k < ts::node_child_count(target); ++k) {
				TSNode c = ts::node_child(target, k);
				if (!found_op) {
					if (ts::node_eq(c, op)) found_op = true;
					continue;
				}
				if (ts::node_eq(c, right)) continue;
				if (c.type() == ";") {
					self.buf.push(token::text(";"));
				} else if (ts::node_is_named(c)) {
					self.process_node(c);
				} else {
					self.buf.push(token::text(c.get_text(self.source_code)));
				}
			}

			// Semicolon of declaration_stmt if any
			if (child.type() == "declaration_stmt" || child.type() == "global_declaration") {
				for (uint s = 1; s < ts::node_child_count(child); ++s) {
					TSNode sc = ts::node_child(child, s);
					if (sc.type() == ";") self.buf.push(token::text(";"));
				}
			}

			if (self.has_trailing_comma(child))
			{
				self.buf.text(",");
			}

			// Handle trailing comment alignment
			if (i + 1 < named_child_count)
			{
				TSNode next = ts::node_named_child(parent, i + 1);
				if (next.start_point_row() == child.end_point_row() && next.is_comment())
				{
					if (self.config.align_comments)
					{
						self.buf.push(token::align(max_comment_col));
					}
					self.buf.push(token::space());
					self.process_comment(next);
					i++; // Skip comment in next iteration
				}
			}

			self.buf.push(token::newline());
		}
		else
		{
			self.process_node(child, true);
		}
		i++;
	}
}


<*
 Format a compound block" like node. Open and close with a specified string (that can contain line return(s)).
 Will then format each subchild. If a child is a "statement" it's its role to append a newline.
 This function will also preserve original blank lines between statements form source code. (can be capped)
 This function will preserve same line comments.
 @param node : "The processed node"
*>
fn void C3Fmt.process_compound(&self, TSNode node)
{
	uint named_child_count = ts::node_named_child_count(node);
	for (uint i = 0; i < named_child_count; ++i)
	{
		TSNode child = ts::node_named_child(node, i);

		int blank_line_amount = 0;
		if (i > 0)
		{
			TSNode sibling = ts::node_named_child(node, i - 1);
			blank_line_amount = child.start_point_row()
				- sibling.end_point_row();
		}
		blank_line_amount = min(
			blank_line_amount,
			self.config.max_blank_line_between_statements + 1
		);

		for (int j = 0; j < blank_line_amount - 1; ++j)
		{
			self.buf.newline();
		}

		// Reattach comment
		if (i > 0 && self.reattach_comment(child, blank_line_amount))
		{
			continue;
		}

		// Alignment logic
		if (self.config.align_assignments && is_alignable_block_node(child))
		{
			uint j = i + 1;
			while (j < named_child_count)
			{
				TSNode next = ts::node_named_child(node, j);
				// If there's a blank line, it breaks the alignment block
				if (next.start_point_row() - ts::node_named_child(node, j - 1).end_point_row() > 1) break;
				if (!is_alignable_block_node(next) && !next.is_comment()) break;
				j++;
			}

			if (j > i + 1)
			{
				self.process_aligned_block(node, i, j);
				i = j - 1;
				continue;
			}
		}

		self.process_node(child, true);
	}
}

faultdef NO_WRAP;
alias AddWrapPointFn = fn WrapPoint?(String type, String field, usz id);
<*
 Format a "line" composed of several nodes.
 Append a white space between each node.

 NOTE: I really like to idea to provide some function argument so special
 note can hook into the logic and add what they want, like it's done for
 wrap_point
 @param node : "The processed node"
 @param skip_space_type : "Do not append a white space before these type"
 @param skip_space_if_after : "Do not append a white space after these type"
 @param append_newline : "If true, will append a newline"
 @param add_wrap_point_fn : "Allow to set wrap point on specific children"
*>
fn void C3Fmt.process_composite(
	&self,
	TSNode node,
	String[] skip_space_type = { ";" },
	String[] skip_space_if_after = { },
	bool append_newline = false,
	AddWrapPointFn add_wrap_point_fn = null,
	usz group_id = 0,
	bool respect_input_newlines = false
)
{
	bool found_inline = false;
	for (uint i = 0; i < ts::node_child_count(node); ++i)
	{
		TSNode child = ts::node_child(node, i);
		String type = child.type();

		String prev_type = i > 0 ? ts::node_child(node, i - 1).type() : "";

		if (i > 0
			&& !(i == 1 && ts::node_child(node, 0).type() == "doc_comment")
			&& !skip_space_type.contains(type)
			&& !skip_space_if_after.contains(prev_type)
			&& !(prev_type.starts_with("$") && (type == "paren_expr" || type == "(")))
		{
			if (respect_input_newlines && child.start_point_row() > ts::node_child(node, i - 1).end_point_row())
			{
				self.buf.newline();
			}
			else
			{
				self.buf.space();
			}
		}

		if (add_wrap_point_fn && self.wrapping_enabled)
		{
			WrapPoint? wrap_point = add_wrap_point_fn(
				type,
				child.field_name(),
				group_id
			);
			if (try wrap_point)
			{
				self.buf.wrap_point(wrap_point);
			}
		}

		if (child.is_comment())
		{
			if (child.type() == "block_comment")
			{
				self.process_block_comment(child);
			}
			if (child.type() == "line_comment")
			{
				self.buf.inline_comment(self.extract_comment_string(child));
				found_inline = true;
			}
		}
		else
		{
			if (ts::node_is_named(child))
			{
				self.process_node(child);
			}
			else
			{
				String text = child.get_text(self.source_code);
				self.buf.text(text);
				if (respect_input_newlines)
				{
					if (text == "{")
					{
						self.indent();
					}
					else if (text == "}")
					{
						self.dedent();
					}
				}
			}
		}
	}

	if (append_newline)
	{
		self.buf.newline();
	}
}

<*
 Rawly format node sequentially, without appending any separator between them.
 Useful for nodes like field accessor ("my_struct.my_field").
 @param node : "The processed node"
*>
fn void C3Fmt.process_sequence(
	&self,
	TSNode node,
	AddWrapPointFn add_wrap_point_fn = null,
	usz group_id = 0
)
{
	for (uint i = 0; i < ts::node_child_count(node); ++i)
	{
		TSNode child = ts::node_child(node, i);

		if (add_wrap_point_fn && self.wrapping_enabled)
		{
			WrapPoint? wrap_point = add_wrap_point_fn(
				child.type(),
				child.field_name(),
				group_id
			);
			if (try wrap_point)
			{
				self.buf.wrap_point(wrap_point);
			}
		}

		if (child.is_comment())
		{
			assert (child.type() == "block_comment");
			self.process_block_comment(child);
		}
		else
		{
			if (ts::node_is_named(child))
			{
				self.process_node(child);
			}
			else
			{
				self.buf.text(child.get_text(self.source_code));
			}
		}
	}
}

<*
 A special function for things like case, $if etc...
 @param node : "The processed node"
*>
fn void C3Fmt.process_uncanny_scope(
	&self,
	TSNode node,
	String scope_enter_type = ":",
	String scope_exit_type = ""
)
{
	bool is_single_line = node.start_point_row() == node.end_point_row();
	usz start_idx = self.buf.len();

	bool entered_scope = false;
	uint entered_scope_id;

	for (uint i = 0; i < ts::node_child_count(node); ++i)
	{
		TSNode child = ts::node_child(node, i);

		if (!entered_scope)
		{
			if (i > 0 && child.type() != ":")
			{
				self.buf.space();
			}

			if (child.is_comment())
			{
				assert (child.type() == "block_comment");
				self.process_block_comment(child);
			}
			else
			{
				if (ts::node_is_named(child))
				{
					self.process_node(child);
				}
				else
				{
					self.buf.text(child.get_text(self.source_code));
				}
			}

			if (child.type() == scope_enter_type)
			{
				entered_scope = true;
				entered_scope_id = i;

				// Check for trailing comment
				if (i < ts::node_child_count(node) - 1)
				{
					TSNode next = ts::node_child(node, i + 1);
					if (next.is_comment() && ts::same_line(child, next))
					{
						self.buf.space();
						self.process_comment(next);
						i++; // advance
					}
				}
				self.buf.newline();
				self.indent();
			}
		}
		else
		{
			int blank_line_amount = 0;
			if (i > entered_scope_id + 1)
			{
				TSNode sibling = ts::node_child(node, i - 1);
				blank_line_amount = child.start_point_row()
					- sibling.end_point_row();
			}
			blank_line_amount = min(
				blank_line_amount,
				self.config.max_blank_line_between_statements + 1
			);

			for (int j = 0; j < blank_line_amount - 1; ++j)
			{
				self.buf.newline();
			}

			// Reattach comment
			if (i > entered_scope_id + 1
				&& self.reattach_comment(child, blank_line_amount, false))
			{
				continue;
			}

			if (child.type() == scope_exit_type)
			{
				assert (!ts::node_is_named(child));
				// The only scope exit i know are $endif $endforeach etc...
				// there are never named so we can just output text
				self.dedent();
				self.buf.text(child.get_text(self.source_code));
				self.buf.newline();

				assert (i == ts::node_child_count(node) - 1);
				if (is_single_line) self.collapse_single_line(start_idx);
				return;
			}

			if (ts::node_is_named(child))
			{
				self.process_node(child, inside_compound: true);
			}
			else
			{
				// a workaround for ';' after compound statements
				if (ts::node_type(child) == ";"
					&& ts::node_type(ts::node_child(node, i - 1))
						== "compound_stmt")
				{
					assert (self.buf.gobble_last_newline());
					self.buf.text(";");
					self.buf.newline();
				}
				else
				{
					self.buf.text(child.get_text(self.source_code));
				}
			}
		}
	}
	self.dedent();
	if (is_single_line) self.collapse_single_line(start_idx);
}

<*
 A special function for ct case stmt.
 @param node : "The processed node"
*>
fn void C3Fmt.process_ct_case_stmt(&self, TSNode node)
{
	bool nl_appended = false;

	for (uint i = 0; i < ts::node_child_count(node); ++i)
	{
		TSNode child = ts::node_child(node, i);
		String type = child.type();

		if (i > 0 && type != ":" && !child.is_comment()
			&& child.type() != "ct_stmt_body")
		{
			self.buf.space();
		}

		if (child.is_comment())
		{
			if (child.type() == "block_comment")
			{
				self.process_block_comment(child);
			}
			if (child.type() == "line_comment")
			{
				if (i == ts::node_child_count(node) - 1)
				{
					io::eprintfn("Found an inline comment as last child?");
					unreachable();
				}

				if (!nl_appended
					&& ts::same_line(
						ts::node_child(node, i - 1),
						child
					)) // as trailing
				{
					self.buf.space();
					self.process_line_comment(child);
					self.buf.newline();
					nl_appended = true;
				}

				else // as comment in body
				{
					if (!nl_appended)
					{
						self.buf.newline();
					}

					self.indent();
					self.process_line_comment(child);
					self.buf.newline();
					self.dedent();

					nl_appended = true;
				}

			}
		}
		else
		{
			if (ts::node_is_named(child))
			{
				if (child.type() == "ct_stmt_body")
				{
					if (!nl_appended)
					{
						self.buf.newline();
					}
					self.indent();
					self.process_node(child);
					self.dedent();
				}
				else
				{
					self.process_node(child);
				}
			}
			else
			{
				self.buf.text(child.get_text(self.source_code));
			}
		}
	}

	if (!node.has_child_of_type("ct_stmt_body") && !nl_appended)
	{
		self.buf.newline();
	}
}

fn void C3Fmt.process_asm_block_stmt(&self, TSNode node)
{
	bool in_scope = false;
	uint in_scope_id;
	for (uint i = 0; i < ts::node_child_count(node); ++i)
	{
		TSNode child = ts::node_child(node, i);
		String type = child.type();

		if (!in_scope)
		{
			String[] skip_space_type = { "(", ")", ";" };
			String[] skip_space_if_after = { "(" };
			if (i > 0 && !skip_space_type.contains(type)
				&& !skip_space_if_after.contains(
					ts::node_child(node, i - 1).type()
				))
			{
				self.buf.space();
			}

			if (child.is_comment())
			{
				if (child.type() == "block_comment")
				{
					self.process_block_comment(child);
				}
				if (child.type() == "line_comment")
				{
					if (i == ts::node_child_count(node) - 1)
					{
						io::eprintfn("Found an inline comment as last child?");
						unreachable();
					}
					self.buf.inline_comment(self.extract_comment_string(child));
				}
			}
			else
			{
				if (ts::node_is_named(child))
				{
					self.process_node(child);
				}
				else
				{
					if (type == "{")
					{
						// TODO
						self.buf.newline();
						self.buf.text("{");
						self.buf.newline();
						self.indent();
						in_scope = true;
						in_scope_id = i;

						continue;
					}
					self.buf.text(child.get_text(self.source_code));
					if (type == ";")
					{
						self.buf.newline();
					}
				}
			}
		}
		else
		{
			if (type == "}")
			{
				self.dedent();
				self.buf.text("}");
				self.buf.newline();

				return; // TODO assert we are finished
			}
			int blank_line_amount = 0;
			if (i > in_scope_id)
			{
				TSNode sibling = ts::node_child(node, i - 1);
				blank_line_amount = child.start_point_row()
					- sibling.end_point_row();
			}
			blank_line_amount = min(
				blank_line_amount,
				self.config.max_blank_line_between_statements + 1
			);

			for (int j = 0; j < blank_line_amount - 1; ++j)
			{
				self.buf.newline();
			}

			// Reattach comment
			if (i > in_scope_id && self.reattach_comment(child, blank_line_amount))
			{
				continue;
			}

			self.process_node(child, true);
		}
	}
}

<*
 Extract raw comment (without // or /* */ delimiters).
 @param comment : "The processed node"
*>
fn String C3Fmt.extract_comment_string(&self, TSNode comment)
{
	assert (comment.is_comment());
	if (comment.type() == "line_comment")
	{
		String text = comment.get_text(self.source_code);
		text = text[2..]; // trim // or #!

		return text.trim();
	}
	else if (comment.type() == "block_comment")
	{
		String text = ts::node_named_child(
			comment,
			0
		).get_text(self.source_code);

		return text.trim();
	}
	unreachable();
}

<*
 Pretty print a comment.
 @param node : "The processed node"
*>
fn void C3Fmt.process_comment(&self, TSNode node)
{
	assert (node.is_comment());

	if (node.type() == "block_comment")
	{
		self.process_block_comment(node);
	}
	if (node.type() == "line_comment")
	{
		self.process_line_comment(node);
	}
}

<*
 Pretty print a block comment.
 @param node : "The processed node"
*>
fn void C3Fmt.process_block_comment(&self, TSNode node)
{
	self.buf.text("/*");
	self.buf.space();
	String comment = self.extract_comment_string(node);
	self.buf.text(comment);
	self.buf.space();
	self.buf.text("*/");

	if (comment == "c3fmt on")
	{
		self.formatter_enabled = true;
	}
	if (comment == "c3fmt off")
	{
		self.formatter_enabled = false;
	}
}

<*
 Pretty print a block comment.
 @param node : "The processed node"
*>
fn void C3Fmt.process_line_comment(&self, TSNode node)
{
	TSNode content = ts::node_named_child(node, 0);

	self.buf.text(node.get_text(self.source_code)[0:2]);
	self.buf.space();
	String comment = self.extract_comment_string(node);
	self.buf.text(comment);

	if (comment == "c3fmt on")
	{
		self.formatter_enabled = true;
	}
	if (comment == "c3fmt off")
	{
		self.formatter_enabled = false;
	}
}
<*
 Pretty print a doc comment.
 @param node : "The processed node"
*>
fn void C3Fmt.process_doc_comment(&self, TSNode node)
{
	self.wrapping_enabled = false;
	uint named_count = ts::node_named_child_count(node);

	bool is_single_line = node.start_point().row == node.end_point().row;

	self.buf.text("<*");
	if (is_single_line)
	{
		self.buf.space();
	}
	else
	{
		self.buf.newline();
	}

	for (uint i = 0; i < named_count; ++i)
	{
		TSNode child = ts::node_named_child(node, i);

		if (!is_single_line)
		{
			int blank_line_amount = 0;
			if (i > 0)
			{
				TSNode sibling = ts::node_named_child(node, i - 1);
				blank_line_amount = child.start_point_row()
					- sibling.end_point_row();
			}
			blank_line_amount = min(
				blank_line_amount,
				self.config.max_blank_line_between_statements + 1
			);

			for (int j = 0; child.type() != "doc_comment_contract"
				&& j < blank_line_amount - 1; ++j)
			{
				self.buf.newline();
			}
			self.buf.space();
		}
		else if (i > 0)
		{
			self.buf.space();
		}

		if (is_single_line)
		{
			if (child.type() == "doc_comment_contract") {
				self.process_composite(child, skip_space_type: { "(", ")", "," }, skip_space_if_after: { "(" });
			} else {
				self.buf.text(child.get_text(self.source_code));
			}
		}
		else
		{
			self.process_node(child, inside_doc_comment: true);
		}
	}

	if (is_single_line)
	{
		self.buf.space();
	}
	else if (named_count == 0)
	{
		self.buf.newline();
	}

	self.buf.text("*>");
	self.buf.newline();
	self.wrapping_enabled = true;
}

fn void C3Fmt.collapse_single_line(&self, usz start_idx)
{
	usz total_len = self.buf.len();
	if (total_len <= start_idx) return;

	for (usz i = start_idx; i < total_len; i++)
	{
		Token t = self.buf[i];
		if (t.kind == TokenKind.INDENT)
		{
			self.indent_level--;
		}
		else if (t.kind == TokenKind.DEDENT)
		{
			self.indent_level++;
		}
	}

	bool last_was_space = false;
	usz write_idx = start_idx;
	for (usz read_idx = start_idx; read_idx < total_len; read_idx++)
	{
		Token t = self.buf[read_idx];

		if (t.kind == NEWLINE || t.kind == INDENT || t.kind == DEDENT)
		{
			if (!last_was_space && write_idx > start_idx)
			{
				self.buf[write_idx++] = token::space();
				last_was_space = true;
			}
		}
		else if (t.kind == WRAP_POINT || t.kind == BEGIN_WRAP_GROUP)
		{
			// skip
		}
		else
		{
			last_was_space = (t.kind == SPACE);
			self.buf[write_idx++] = t;
		}
	}

	while (self.buf.len() > write_idx)
	{
		(void)self.buf.pop();
	}
	self.buf.push(token::newline());
}

<*
 Process a node of an unknown type
*>
fn void C3Fmt.process_node(
	&self,
	TSNode node,
	bool inside_compound = false,
	bool inside_doc_comment = false
)
{
	switch (node.type())
	{
		/* ======================================== */
		/* TOP-LEVEL */
		/* ======================================== */
		case "source_file":
			self.process_compound(node);
		case "hashbang_line":
			self.process_comment(node);
			self.buf.newline();

		/* ======================================== */
		/* FUNCTIONS, MACROS & LAMBDAS */
		/* ======================================== */
		case "func_declaration":
			self.process_composite(
				node,
				skip_space_type: { ";", "func_param_list", "generic_param_list", "generic_arg_list" },
			);
		case "interface_func_declaration":
			self.process_composite(
				node,
				skip_space_type: { ";", "func_param_list", "generic_param_list", "generic_arg_list" },
				append_newline: true
			);
		case "func_definition":
			self.process_composite(
				node,
				skip_space_type: { "func_param_list", "macro_func_body", "generic_param_list", "generic_arg_list" },
				append_newline: true
			);
		case "func_header":
			self.process_composite(
				node,
				skip_space_type: { "." },
				skip_space_if_after: { "." },
			);
		case "func_param_list":
			usz id = self.begin_wrap_group(2);
			self.process_composite(
				node,
				skip_space_type: { ")", "," },
				skip_space_if_after: { "(" },
				add_wrap_point_fn: fn (String type, String field, usz id)
			{
				switch (type)
				{
					case "param":
						return { .indent = 1, .group_id = id };
					case ")":
						return { .indent = 0, .group_id = id };
					default:
						return NO_WRAP~;
				}
			}, group_id: id);
		case "param":
			self.process_composite(node, skip_space_if_after: { "&" },);
		case "param_default":
			self.process_composite(node);
		case "lambda_declaration":
			self.process_composite(node);
		case "macro_declaration":
			self.process_composite(
				node,
				skip_space_type: { "macro_param_list", "macro_func_body" },
				append_newline: true
			);
		case "macro_header":
			self.process_composite(
				node,
				skip_space_type: { "." },
				skip_space_if_after: { "." },
			);
		case "macro_param_list":
			if (node.has_child_of_type("param"))
			{
				usz id = self.begin_wrap_group(2);
				self.process_composite(
					node,
					skip_space_type: { ")", ",", ";" },
					skip_space_if_after: { "(" },
					add_wrap_point_fn: fn (String type, String field, usz id)
				{
					switch (type)
					{
						case "param":
							return { .indent = 1, .group_id = id };
						case ")":
							return { .indent = 0, .group_id = id };
						default:
							return NO_WRAP~;
					}
				}, group_id: id);
			}
			else
			{
				self.process_composite(
					node,
					skip_space_type: { ")", ",", ";" },
					skip_space_if_after: { "(" }
				);
			}
		case "trailing_block_param":
			self.process_sequence(node);
		case "macro_func_body":
			TSNode child = ts::node_child(node, 0);
			switch (child.type())
			{
				case "compound_stmt":
					self.buf.newline();
					self.buf.text("{");
					self.buf.newline();
					self.indent();
					self.process_compound(child);
					self.dedent();
					self.buf.text("}");
				case "implies_body":
					self.buf.space();
					self.process_composite(node, append_newline: false);
				case "=>":
					self.buf.space();
					self.process_composite(node, append_newline: false);
				case "call_expr":
					self.buf.space();
					self.buf.text("=>");
					self.buf.space();
					self.process_node(child);
			}
		case "implies_body":
			self.process_composite(node);
		case "=>":
			self.process_composite(node);

		/* ======================================== */
		/* DECLARATION */
		/* ======================================== */
		case "struct_declaration":
			self.process_composite(
				node,
				skip_space_type: { "generic_param_list", "generic_arg_list" },
				append_newline: true
			);
		case "struct_body":
			self.buf.newline();
			self.buf.text("{");
			self.buf.newline();
			self.indent();
			self.process_compound(node);
			self.dedent();
			self.buf.text("}");
		case "struct_member_declaration":
			self.process_composite(node, append_newline: true);
		case "enum_declaration":
			self.process_composite(
				node,
				skip_space_type: { "generic_param_list", "generic_arg_list" },
				append_newline: true
			);
		case "constdef_declaration":
			self.process_composite(
				node,
				skip_space_type: { "generic_param_list", "generic_arg_list" },
				append_newline: true
			);
		case "enum_spec":
			self.process_composite(node);
		case "enum_body":
			self.buf.newline();
			self.buf.text("{");
			self.buf.newline();
			self.indent();
			self.process_compound(node);
			self.dedent();
			self.buf.text("}");
		case "enum_constant":
			self.process_composite(node);

			bool has_comma = false;
			TSNode parent = ts::node_parent(node);
			bool start_searching;
			for (uint i = 0; i < ts::node_child_count(parent); ++i)
			{
				TSNode child = ts::node_child(parent, i);
				if (ts::node_eq(child, node))
				{
					start_searching = true;
				}
				if (start_searching)
				{
					if (child.type() == ",")
					{
						has_comma = true;
						break;
					}
					if (child.type() == "}")
					{
						break;
					}
				}
			}

			if (has_comma)
			{
				self.buf.text(",");
			}

			self.buf.newline();
		case "enum_arg":
			self.process_composite(node);
		case "enum_param_list":
			self.process_composite(
				node,
				skip_space_type: { ",", ")" },
				skip_space_if_after: { "(" }
			);
		case "enum_param":
			self.process_composite(node);
		case "bitstruct_declaration":
			self.process_composite(
				node,
				skip_space_type: { "generic_param_list", "generic_arg_list" },
				append_newline: true
			);
		case "bitstruct_body":
			self.buf.newline();
			self.buf.text("{");
			self.buf.newline();
			self.indent();
			self.process_compound(node);
			self.dedent();
			self.buf.text("}");
		case "bitstruct_member_declaration":
			self.process_composite(
				node,
				skip_space_type: { "..", ";" },
				skip_space_if_after: { ".." },
				append_newline: true
			);
		case "interface_declaration":
			self.process_composite(
				node,
				skip_space_type: { "," },
				append_newline: true
			);
		case "interface_body":
			self.buf.newline();
			self.buf.text("{");
			self.buf.newline();
			self.indent();
			self.process_compound(node);
			self.dedent();
			self.buf.text("}");
		case "faultdef_declaration":
			uint start_row = node.start_point().row;
			for (uint i = 0; i < ts::node_child_count(node); ++i)
			{
				TSNode child = ts::node_child(node, i);
				if (child.type() == "faultdef")
				{
					start_row = child.start_point().row;
					break;
				}
			}
			bool is_multi = start_row != node.end_point().row;
			for (uint i = 0; i < ts::node_child_count(node); ++i)
			{
				TSNode child = ts::node_child(node, i);
				String type = child.type();

				if (type == "doc_comment")
				{
					self.process_node(child);
					continue;
				}

				if (type == "faultdef")
				{
					self.buf.text("faultdef");
					if (is_multi)
					{
						self.buf.newline();
						self.indent();
					}
					continue;
				}

				if (type == ";")
				{
					if (is_multi)
					{
						self.buf.newline();
						self.dedent();
					}
					self.buf.text(";");
					self.buf.newline();
					continue;
				}

				if (i > 0 && type != "," && type != ";")
				{
					// Avoid space after faultdef if is_multi
					// AND avoid space after a line comment (which already broke the line)
					if (!(ts::node_child(node, i - 1).type() == "faultdef" && is_multi)
						&& ts::node_child(node, i - 1).type() != "line_comment")
					{
						self.buf.space();
					}
				}

				if (child.is_comment())
				{
					self.buf.inline_comment(self.extract_comment_string(child));
				}
				else if (ts::node_is_named(child))
				{
					self.process_node(child);
				}
				else
				{
					self.buf.text(child.get_text(self.source_code));
				}
			}
		case "attrdef_declaration":
			self.process_composite(
				node,
				skip_space_type: { ";", "attribute_param_list" },
				append_newline: true
			);
		case "module_declaration":
			self.process_composite(
				node,
				skip_space_type: { ",", ";" },
				append_newline: true
			);
		case "import_declaration":
			self.process_composite(
				node,
				skip_space_type: { ",", ";" },
				append_newline: true
			);
		case "import_path":
			self.process_composite(node);
		case "path_ident":
			self.process_sequence(node);
		case "module_resolution":
			self.process_sequence(node);
		case "path_type_ident":
			self.process_sequence(node);
		case "path_at_type_ident":
			self.process_sequence(node);
		case "typedef_declaration":
			self.process_composite(node, append_newline: true);
		case "alias_declaration":
			self.process_composite(node, append_newline: true);
		case "func_signature":
			self.process_composite(
				node,
				skip_space_type: { "func_param_list", "generic_param_list", "generic_arg_list" }
			);
		case "var_declaration":
			self.process_composite(node);

		/* ======================================== */
		/* EXPRESSIONS */
		/* ======================================== */
		case "call_inline_attributes":
			self.process_composite(node);
		case "attributes":
			self.process_composite(node);
		case "attribute":
			self.process_sequence(node);
		case "attribute_arg_list":
			self.process_composite(
				node,
				skip_space_type: { ",", ")" },
				skip_space_if_after: { "(" },
			);
		case "attribute_arg":
			self.process_sequence(node);
		case "access_ident":
			self.process_sequence(node);
		case "access_eval":
			self.process_sequence(node);
		case "flat_path":
			self.process_sequence(node);
		case "type":
			self.process_sequence(node);
		case "type_suffix":
			self.process_composite(
				node,
				skip_space_type: { "[<", ">]", "[", "]" },
				skip_space_if_after: { "[<", "[" }
			);
		case "identifier_list":
			self.process_composite(node, skip_space_type: { "," });
		case "attribute_list":
			self.process_composite(node, skip_space_type: { "," },);
		case "attribute_param_list":
			self.process_composite(
				node,
				skip_space_type: { ",", ")" },
				skip_space_if_after: { "(" },
			);
		case "paren_cond":
			self.process_composite(
				node,
				skip_space_type: { ")" },
				skip_space_if_after: { "(" },
			);
		case "try_unwrap":
			self.process_composite(node);
		case "catch_unwrap_list":
			self.process_composite(
				node,
				skip_space_type: { "," },
				skip_space_if_after: { "(" },
			);
		case "catch_unwrap":
			self.process_composite(node);
		case "call_expr":
			self.process_composite(node, skip_space_type: { "call_arg_list", "generic_arg_list" });
		case "call_arg_list":
			if (node.has_child_of_type("call_arg"))
			{
				usz id = self.begin_wrap_group(2);
				self.process_composite(
					node,
					skip_space_type: { ")", "," },
					skip_space_if_after: { "(" },
					add_wrap_point_fn: fn (String type, String field, usz id)
				{
					switch (type)
					{
						case ")":
							return { .indent = 0, .group_id = id };
						case "call_arg":
							return { .indent = 1, .group_id = id };
						default:
							return NO_WRAP~;
					}
				}, group_id: id);
			}
			else
			{
				self.process_composite(
					node,
					skip_space_type: { ")", "," },
					skip_space_if_after: { "(" }
				);
			}
		case "call_args":
			self.process_composite(node);
		case "call_arg":
			self.process_composite(
				node,
				skip_space_type: { ":", "range_expr", "[", "]" },
				skip_space_if_after: { "[", "..." },
			);
		case "ternary_expr":
			self.process_composite(node);
		case "elvis_orelse_expr":
			self.process_composite(node);
		case "maybe_deref_expr":
			self.process_sequence(node);
		case "binary_expr":
			usz id = self.begin_wrap_group(2);
			self.process_composite(
				node,
				add_wrap_point_fn: fn (String type, String field, usz id)
			{
				if(type == "<" || type == "<=" || type == ">" || type == ">=") {
					return NO_WRAP~;
				}
				switch (field)
				{
					case "operator":
						return { .indent = 1, .group_id = id };
					default:
						return NO_WRAP~;
				}
			}, group_id: id);
		case "assignment_expr":
			self.process_composite(node);
		case "paren_expr":
			self.process_composite(
				node,
				skip_space_type: { ")" },
				skip_space_if_after: { "(" },
			);
		case "lambda_expr":
			self.process_composite(node);
		case "type_paren_expr":
			self.process_composite(
				node,
				skip_space_type: { ")" },
				skip_space_if_after: { "(" },
			);
		case "initializer_list":
			if (node.has_child_of_type("initializer_element"))
			{
				bool is_manual_multiline = node.start_point_row() != node.end_point_row();
				uint count = ts::node_named_child_count(node);

				if (is_manual_multiline && count > 10)
				{
					self.process_composite(node, skip_space_type: { "," }, respect_input_newlines: true);
				}
				else
				{
					usz id = self.begin_wrap_group(2);
					self.process_composite(
						node,
						skip_space_type: { "," },
						add_wrap_point_fn: fn (String type, String field, usz id)
					{
						switch (type)
						{
							case "initializer_element":
								return { .indent = 1, .group_id = id };
							case "}":
								return { .indent = 0, .group_id = id };
							default:
								return NO_WRAP~;
						}
					}, group_id: id);
				}
			}
			else
			{
				self.process_composite(node, skip_space_type: { "," });
			}
		case "comma_decl_or_expr":
			self.process_composite(
				node,
				skip_space_type: { ",", ")" },
				skip_space_if_after: { "(" }
			);
		case "interface_impl_list":
			self.process_composite(
				node,
				skip_space_type: { ",", ")" },
				skip_space_if_after: { "(" }
			);
		case "trailing_generic_expr":
			self.process_composite(node, skip_space_type: { "generic_arg_list" });
		case "generic_type_ident":
			self.process_composite(node, skip_space_type: { "generic_arg_list" });
		case "generic_arg_list":
			self.process_composite(
				node,
				skip_space_type: { "}", ">", "," },
				skip_space_if_after: { "{", "<" },
			);
		case "generic_param_list":
			self.process_composite(
				node,
				skip_space_type: { ">", "," },
				skip_space_if_after: { "<" },
			);
		case "initializer_element":
			self.process_composite(node);
		case "param_path":
			self.process_sequence(node);
		case "typed_initializer_list":
			self.process_composite(
				node,
				skip_space_type: { ")" },
				skip_space_if_after: { "(" },
			);
		case "param_path_element":
		case "unary_expr":
		case "update_expr":
		case "optional_expr":
		case "cast_expr":
		case "field_expr":
			if (node.has_child_of_type(".")
				&& ts::node_parent(node).type() != "param_path")
			{
				usz id = self.begin_wrap_group(0);
				self.process_sequence(
					node,
					add_wrap_point_fn: fn (String type, String field, usz id)
				{
					switch (type)
					{
						case ".":
							return { .indent = 1, .group_id = id };
						default:
							return NO_WRAP~;
					}
				}, group_id: id);
			}
			else
			{
				self.process_sequence(node);
			}
		case "subscript_expr":
		case "range_expr":
		case "rethrow_expr":
		case "type_access_expr":
			self.process_sequence(node);


		/* ======================================== */
		/* STATEMENTS & CONTROL FLOW */
		/* ======================================== */
		case "compound_stmt":
			if (!inside_compound)
			{
				// shitty workaround to handle compound stmt
				// for scope decl
				self.buf.newline();
			}

			self.buf.text("{");
			self.buf.newline();
			self.indent();
			self.process_compound(node);
			self.dedent();
			self.buf.text("}");

			if (inside_compound)
			{
				self.buf.newline();
			}
		case "var_stmt":
			self.process_composite(node, append_newline: true);
		case "expr_stmt":
			self.process_composite(
				node,
				skip_space_type: { ";", ",", ")", "(" },
				skip_space_if_after: { "(" },
				append_newline: true
			);
		case "defer_stmt":
			self.process_composite(
				node,
				append_newline: node.has_child_of_type("compound_stmt")
			);
		case "defer_catch_ident":
			self.process_composite(
				node,
				skip_space_type: { ")" },
				skip_space_if_after: { "(" },
				append_newline: true
			);
		case "return_stmt":
			self.process_composite(node, append_newline: true);
		case "break_stmt":
			self.process_composite(node, append_newline: true);
		case "nextcase_stmt":
			self.process_composite(
				node,
				skip_space_type: { ";", ":" },
				append_newline: true
			);
		case "continue_stmt":
			self.process_composite(node, append_newline: true);
		case "assert_stmt":
			self.process_composite(
				node,
				skip_space_type: { ";", ")" },
				skip_space_if_after: { "(" },
				append_newline: true
			);
		case "for_stmt":
			TSNode body = node.get_child_with_field("body");
			self.process_composite(
				node,
				append_newline: (body.type() == "compound_stmt" || body.type() == ";")
			);
		case "for_cond":
			self.process_composite(
				node,
				skip_space_type: { ";", ")" },
				skip_space_if_after: { "(" },
			);
		case "foreach_stmt":
			TSNode body = node.get_child_with_field("body");
			self.process_composite(
				node,
				append_newline: body.type() == "compound_stmt"
			);
		case "foreach_cond":
			self.process_composite(
				node,
				skip_space_type: { ",", ")" },
				skip_space_if_after: { "(" },
			);
		case "foreach_var":
			self.process_composite(node, skip_space_if_after: { "&" },);
		case "while_stmt":
			TSNode body = node.get_child_with_field("body");
			self.process_composite(
				node,
				append_newline: body.type() == "compound_stmt"
			);
		case "do_stmt":
			self.process_composite(node, append_newline: true);
		case "if_stmt":
			TSNode body = node.get_child_with_field("body");
			TSNode parent = ts::node_parent(node);
			self.process_composite(
				node,
				append_newline: body.type() == "compound_stmt"
					&& !node.has_child_of_type("else_part")
			);
		case "else_part":
			if (self.config.else_on_newline)
			{
				self.buf.newline();
			}
			self.process_composite(
				node,
				append_newline: !node.has_child_of_type("if_stmt")
			);
		case "switch_stmt":
			self.process_composite(
				node,
				skip_space_type: { "switch_body" },
				append_newline: true
			);
		case "switch_body":
			self.buf.newline();
			self.buf.text("{");
			self.buf.newline();
			self.indent();
			self.process_compound(node);
			self.dedent();
			self.buf.text("}");
		case "case_stmt":
			self.process_uncanny_scope(node, ":");
		case "default_stmt":
			self.process_uncanny_scope(node, ":");
		case "case_range":
			self.process_sequence(node);
		case "asm_block_stmt":
			self.process_asm_block_stmt(node);
		case "asm_stmt":
			self.process_composite(
				node,
				skip_space_type: { ";", "," },
				append_newline: true
			);
		case "asm_instr":
			self.buf.text(node.get_text(self.source_code));
		case "asm_expr":
			self.process_sequence(node);
		case "asm_addr":
			self.process_composite(
				node,
				skip_space_type: { "]" },
				skip_space_if_after: { "[" }
			);
		case "ct_assert_stmt":
			self.process_composite(
				node,
				skip_space_type: { ";", ")", "," },
				skip_space_if_after: { "(" },
				append_newline: true
			);
		case "ct_echo_stmt":
			self.process_composite(node, append_newline: true);
		case "ct_include_stmt":
			self.process_composite(node, append_newline: true);
		case "ct_exec_stmt":
			self.process_composite(
				node,
				skip_space_type: { ";", ")", "," },
				skip_space_if_after: { "(" },
				append_newline: true
			);
		case "ct_stmt_body":
			self.process_compound(node);
		case "ct_if_stmt":
			self.process_uncanny_scope(
				node,
				scope_enter_type: "ct_if_cond",
				scope_exit_type: "$endif"
			);
		case "ct_if_cond":
			self.process_sequence(node);
		case "ct_else_stmt":
			self.dedent(); // restick
			self.process_uncanny_scope(node, scope_enter_type: "$else");
			if (try t = self.buf.last()) {
				if (t.kind == DEDENT) (void)self.pop_token();
			}
		case "ct_for_stmt":
			self.process_uncanny_scope(node, scope_exit_type: "$endfor");
		case "ct_for_cond":
			self.process_composite(node);
		case "ct_foreach_stmt":
			self.process_uncanny_scope(node, scope_exit_type: "$endforeach");
		case "ct_foreach_cond":
			self.process_composite(node, skip_space_type: { "," },);
		case "ct_switch_stmt":
			self.process_uncanny_scope(node, scope_exit_type: "$endswitch");
		case "ct_switch_cond":
			self.process_composite(node, skip_space_type: { "," },);
		case "ct_case_stmt":
			self.process_ct_case_stmt(node);

		/* ======================================== */
		/* COMMENTS */
		/* ======================================== */
		case "block_comment":
			self.process_block_comment(node);
			self.buf.newline();
		case "line_comment":
			self.process_line_comment(node);
			self.buf.newline();
		case "doc_comment":
			self.process_doc_comment(node);
		case "doc_comment_text":
			self.buf.text(node.get_text(self.source_code));
			self.buf.newline();
		case "doc_comment_contract":
			self.process_composite(
				node,
				skip_space_type: { "(", ")", "," },
				skip_space_if_after: { "(" },
				append_newline: true
			);

		/* ======================================== */
		/* COMMON LEAVES */
		/* ======================================== */
		case "ident":
		case "ident_expr":
		case "ct_ident":
		case "at_ident":
		case "hash_ident":
		case "const_ident":
		case "ct_const_ident":
		case "type_ident":
		case "base_type_name":
		case "ct_type_ident":
		case "at_type_ident":
		case "builtin":
		case "builtin_const":
		case "$feature":
		case "$defined":
		case "$typeof":
		case "$sizeof":
		case "$embed":
		case "$vacount":
		case "$vaconst":
		case "$vaarg":
		case "$vaexpr":
		case "$eval":
		case "$is_const":
		case "$stringify":
		case "$kindof":
		case "$assignable":
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
		case "overload_operator":
		case "doc_comment_contract_descriptor":
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
			self.process_composite(node, append_newline: true);

		default:
			io::eprintfn(
				"Type %s is not supported by c3fmt (yet!). Around line %s",
				node.type(),
				node.start_point_row()
			);
			self.buf.text(node.get_text(self.source_code));
			self.buf.newline();
			// unreachable();
	}
}