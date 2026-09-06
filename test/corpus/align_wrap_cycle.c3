module align_wrap_cycle;

fn void aligning_a_rethrow_call_must_not_overflow_the_line()
{
	double[12] points = { 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0 };
	sz face = shapes::loop_from_points(&b, points[..], 4)!!;
	sz bridge = b.edges.len();
	sz other = b.mef(0, shapes::find_he_targeting(&b, face, 0)!!, 2, shapes::find_he_targeting(&b, face, 2)!!)!!;
}

fn void a_run_that_fits_still_aligns()
{
	sz face   = loop_from_points(&b, points, 4)!!;
	sz bridge = b.edges.len();
}
