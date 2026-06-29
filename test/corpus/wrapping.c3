fn int main (String a__long__arg, String a__long__arg = "Hello", int a_third_arg = 30) {
    main(a__long__arg: "a very long string that will go beyond 80 words", a__long__arg: "", 30);

    main(a__long__arg: "a long string", a__long__arg: "", //
        30
    );

    main(//
        a__long__arg: "a very long string that will go beyond 80 words", //
		a_third: 30, //
        a__long__arg: "", 30
    );

	RenderingInfo rendering_info = vk::renderingInfo()
		.setLayerCount(1)
		.setRenderArea({
			.offset = { .x = 0, .y = 0 },
			.extent = context.extent,
		});
}

fn int Termios.setAttr(&self, Fd fd, Tcactions optional_actions) @deprecated => self.set_attr(fd, optional_actions);

Pipeline a = {
		{
		.offset = "a very long string that will go beyond 80 words",// Todo: Add CameraData offset here
		.range = "a very long string that will go beyond 80 words"
		}
};

faultdef SAMPLE_ALPHA, SAMPLE_BETA, SAMPLE_GAMMA, SAMPLE_DELTA, SAMPLE_EPSILON, SAMPLE_ZETA, SAMPLE_ETA, SAMPLE_THETA, SAMPLE_IOTA;

fn void wrap_assignment_expr()
{
	ParserState* state = (ParserState*)raw;
	WorkItem* item = (WorkItem*)state.owner;
	Handler handler = item.handler;
	bool paused = (state.flags & SAMPLE_FLAG_DISABLED) != 0;
	bool ready = !state.error_code;
	ulong total_count = ready ? compute_total_count(context, state, item) : 0;
	bool should_continue = ready && !paused && (long)item.interval > 0 && total_count <= (ulong)item.remaining_count;
}

fn void wrap_assignment_expr_stable()
{
	ParserState* state  = (ParserState*)raw;
	WorkItem* item      = (WorkItem*)state.owner;
	Handler handler     = item.handler;
	bool paused         = (state.flags & SAMPLE_FLAG_DISABLED) != 0;
	bool ready          = !state.error_code;
	ulong total_count   = ready ? compute_total_count(context, state, item) : 0;
	bool should_continue = ready && !paused && (long)item.interval > 0
		&& total_count <= (ulong)item.remaining_count;
}
