macro func1(args...)
{
}

macro func1(args...)
{
}

fn void func2(int ...args)
{
}

fn void func3(int ...args)
{
}

fn void spread_test()
{
	result = { ...result, .a = 1 };
	result = { ...result, ...other_thing };
}
