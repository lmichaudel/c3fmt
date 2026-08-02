/* Treesitter Helpers */
module ts;

fn uint TSNode.start_point_row(self)
{
	TSPoint position = ts::node_start_point(self);
	return position.row;
}

fn uint TSNode.end_point_row(self)
{
	TSPoint position = ts::node_end_point(self);
	return position.row;
}

fn TSNode TSNode.get_child_with_field(self, String field_name)
{
	for (uint i = 0; i < ts::node_child_count(self); ++i)
	{
		TSNode child = ts::node_child(self, i);
		if (child.field_name() == field_name)
		{
			return child;
		}
	}

	unreachable();
}

fn bool TSNode.has_child_with_field(self, String field_name)
{
	for (uint i = 0; i < ts::node_child_count(self); ++i)
	{
		TSNode child = ts::node_child(self, i);
		if (child.field_name() == field_name)
		{
			return true;
		}
	}

	return false;
}

fn bool TSNode.has_child_of_type(self, String type)
{
	for (uint i = 0; i < ts::node_child_count(self); ++i)
	{
		if (ts::node_child(self, i).type() == type)
		{
			return true;
		}
	}

	return false;
}

fn String TSNode.field_name(self)
{
	TSNode parent = ts::node_parent(self);

	for (uint i = 0; i < ts::node_child_count(parent); ++i)
	{
		TSNode child = ts::node_child(parent, i);
		if (ts::node_eq(child, self))
		{
			ZString field_name = ts::node_field_name_for_child(parent, i);
			return field_name == null ? "<NULL>" : field_name.str_view();
		}
	}

	unreachable();
}

fn bool TSNode.is_comment(self)
{
	String node_type = self.type();

	return node_type == "line_comment" || node_type == "block_comment";
}

fn bool same_line(TSNode a, TSNode b)
{
	return a.end_point_row() == b.start_point_row();
}

fn bool String[].contains(&self, String str)
{
	foreach (String token : self)
	{
		if (token == str)
		{
			return true;
		}
	}

	return false;
}

import std::io;

// checks semantic of the named node only
fn bool same_semantic(TSNode a, TSNode b)
{
	if (a.type() != b.type() && !(a.is_comment() && b.is_comment()))
	{
		return false;
	}

	uint a_cc = ts::node_named_child_count(a);
	uint b_cc = ts::node_named_child_count(b);

	if (a_cc != b_cc && !(a.is_comment() && b.is_comment()))
	{
		return false;
	}

	for (uint i = 0; i < a_cc; ++i)
	{
		if (!same_semantic(ts::node_named_child(a, i), ts::node_named_child(b, i)))
		{
			return false;
		}
	}

	return true;
}

fn bool TSNode.contains_node(self, TSNode other)
{
	if (ts::node_is_null(self) || ts::node_is_null(other)) return false;
	return other.start_byte() >= self.start_byte() && other.end_byte() <= self.end_byte();
}

fn bool TSNode.ends_with_trailing_comma(self, String closing_delimiter)
{
	for (int i = (int)ts::node_child_count(self) - 1; i >= 0; i--)
	{
		TSNode child = ts::node_child(self, (uint)i);
		String type  = child.type();

		if (type == closing_delimiter || child.is_comment())
		{
			continue;
		}

		return type == ",";
	}

	return false;
}
