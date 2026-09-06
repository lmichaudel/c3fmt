module sequence_line_comment;

fn void line_comment_in_method_chain()
{
	int y = foo(). // note
		bar();
}
