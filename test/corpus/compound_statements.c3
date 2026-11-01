fn void f()
{
	int a = 1;
	{
		a++;
	}
	int b = 2;
}

fn void first_stmt()
{
	{
		int x = 10;
	}
}

fn void nested()
{
	int a = 1;
	{
		int b = 2;
		{
			int c = 3;
		}
	}
	int d = 4;
}

fn void with_blank_lines()
{
	int a = 1;

	{
		a++;
	}

	int b = 2;
}
