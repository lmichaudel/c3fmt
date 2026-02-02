/* a cool but one line block */

/* a cool multiline block
comment */
fn void main()
{
	int a /* zea */ = 10; // set a equal to 10
	int b = 10 /* zea */; /* zea */

	// classic comment
	for (int j = /* zea */ 0; j < 10; /* zea */ ++j)
	{
		// comment
		// another
		main(); // a last
	}

	mystruct/* i'm a psycho */.field = 10;
}

<*
 @require foo > 0, foo < 1000 : "optional error msg"
*>
fn void main ()
{

}

<*
 @require foo != null
 @ensure return > foo.x
*>
import module;

<*
 @param [&in] i
*>
alias name = type;

<*
 @require $defined(resource.open, resource.open()) : `Expected resource to have an "open" function`
 @require resource != nil
 @require $assignable(resource.open(), void*)
*>
faultdef FAULT;