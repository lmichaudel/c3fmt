fn void func1(int value,)
{
}

fn void func2(int first, int second,)
{
}

fn void trailing_comma_test()
{
	func1(value,);
	func2(first, second,);

	func1(value);
	func2(first, second);
}
