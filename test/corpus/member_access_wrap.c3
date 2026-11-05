module m;

fn void f()
{
	foreach (e : entities)
	{
		e.setPosition(
			{
				e.getPosition().x,
				(math::sin(state.t) * AMPLITUDE) + constants::SCREEN_HEIGHT / 2.0f - i * 30.0f + 12345.0f
			}
		);
	}
}

fn void f_trailing()
{
	foreach (e : entities)
	{
		e.setPosition(
			{
				e.getPosition().x,
				(math::sin(state.t) * AMPLITUDE) + constants::SCREEN_HEIGHT / 2.0f - i * 30.0f + 12345.0f,
			}
		);
	}
}

fn void f_manual_breaks()
{
	foreach (e : entities)
	{
		e.setPosition(
			{
				e.getPosition().x,
				(math::sin(state.t) * AMPLITUDE) + constants::SCREEN_HEIGHT / 2.0f - i * 30.0f + 12345.0f
			}
		);
	}
}