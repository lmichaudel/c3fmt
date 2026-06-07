fn void foo() {
		ulong i = int_from_5_chars(r[0], r[1], r[2], r[3], r[4]);
		ch =
			i == int_from_5_chars('l','t', 0,  0, 0) ? '<' :
			i == int_from_5_chars('g','t', 0,  0, 0) ? '>' :
			i == int_from_5_chars('a','m','p', 0, 0) ? '&' :
			i == int_from_5_chars('a','p','o','s',0) ? '\'':
			i == int_from_5_chars('q','u','o','t',0) ? '"' : 0;
}

fn void bar() {
	ch =	i == int_from_5_chars('l','t', 0,  0, 0) ? '<' : 0;
}