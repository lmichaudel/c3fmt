fn void update_record(Source* source)
{
	ExtremelyLongComputationContext* context = (ExtremelyLongComputationContext*)source.context;
	Result result = build_record(source.primary_value, context, source.secondary_value, source.tertiary_value);
	(void)result;
}
