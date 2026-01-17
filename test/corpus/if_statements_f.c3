fn void main()
{
	if (a == 10 && (b == 20 || c <= 21)) main();

	if (true)
	{
		main();
		main();
		return;
	}

	if (true)
	{
		main();
		main();
		return;
	}
	else
	{
		return;
	}

	if (true)
	{
	}
	else if (false)
	{
	}
	else if (true)
	{
	}
	else
	{
	}

	$if $x > 3: // comment
		main();
		// com
	$else // trail
		// comm1
		#y += $x; // comm2
	$endif // aa
}