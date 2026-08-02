constdef ErrorCode : long
{
	<*
	 Defined in the LSP specification, but in the range reserved for JSON-RPC
error codes, namely the -32099 to -32000 "Reserved for implementation-defined server-errors"
	*>
	SERVER_NOT_INITIALIZED = -32002
}

/* a cool but one line block */

/* a cool multiline block
comment */
fn void main () {
    int a
    /* zea */= 10; // set a equal to 10
    int b = 10/* zea */;/* zea */

    // classic comment
    for (int j =/* zea */ 0; j < 10; /* zea */++j) { // comment
        // another
        main(); // a last
    }

    mystruct/* i'm a psycho */.field = 10;
}

<*
	This is a very long doc comment line that exceeds the max column limit of eighty characters and will wrap nicely.
*>
fn void long_doc_comment_wrap()
{
	int x = 1;
}

<*
 @require foo > 0, foo < 1000 : "optional error msg"
*>
fn void main () {}

<*
 @require foo != null
 @ensure return > foo.x
*>
import module @private, other @public;

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