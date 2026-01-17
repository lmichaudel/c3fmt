fn void example_foreach(float[] values)
{
	foreach (index, value : values)
	{
		io::printfn("%d: %f", index, value);
	} // comment

	foreach (usz /*aa*/ index, value : values) io::printfn(
		"%d: %f",
		index,
		value
	);

	foreach (&value : values)
	{
		*value *= 2;
	}
}