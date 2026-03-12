struct Bar
{
	int y;
}

struct Foo
{
	Bar x;
}

fn void main()
{
	int a = 4;
	Foo as;
	as = { .x.y = 3 };
}