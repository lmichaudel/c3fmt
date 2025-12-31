fn void main () {
    switch MAIN: (enum_var)
    {
        case FOO:
            switch (i)
            {
                case 1:
                    doSomething(); // do
                    nextcase 3; // Jump to case 3
                case 2:
                    doSomethingElse();
                case 3:
                    nextcase rand(); // Jump to random case
                default:
                    io::printn("Ended");
                    nextcase MAIN: BAR;  // Jump to outer (MAIN) switch
            }
        case BAR:
            io::printn("BAR");
        default:
            break;
    }

    switch (true)
    {
        case x < 0:
            xless();
        case x > 0:
            xgreater();
        default:
            xequals();
    }

    switch (i)
    {
        case 1:
            doSomething();
            nextcase; // Jumps to case 2
        case 2:
            doSomethingElse();
    }
}

enum Height : uint
{
    LOW,
    MEDIUM,
    HIGH
}

fn void demo_enum(Height h)
{
    switch (h)
    {
        case LOW:
        case MEDIUM:
            io::printn("Not high");
            // Implicit break.
        case HIGH:
            io::printn("High");
    }

    // This also works
    switch (h)
    {
        case LOW:
        case MEDIUM:
            io::printn("Not high");
            // Implicit break.
        case Height.HIGH:
            io::printn("High");
    }

    // Completely empty cases are not allowed.
    switch (h)
    {
        case LOW:
            break; // Explicit break required, since switches can't be empty.
        case MEDIUM:
            io::printn("Medium");
        case HIGH:
            break;
    }

    // special checking of switching on enum types
    switch (h)
    {
        case LOW:
        case MEDIUM:
        case HIGH:
            break;
        default:    // warning: default label in switch which covers all enumeration value
            break;
    }

    // Using "nextcase" will fallthrough to the next case statement,
    // and each case statement starts its own scope.
    switch (h)
    {
        case LOW:
            int a = 1;
            io::printn("A");
            nextcase;
        case MEDIUM:
            int a = 2;
            io::printn("B");
            nextcase;
        case HIGH:
            // a is not defined here
            io::printn("C");
    }
}

macro @foo($x, #y)
{
    $switch $x:
    $endswitch

    $switch:
        $case $x > 10:
            #y += $x * $x;
        $case $x < 0:
            #y += $x;
        $default:
            #y -= $x;
    $endswitch

    $switch $x:  // com
        $case 1:
        //com
            #y += $x * $x;
        $case 2:
            #y += $x; // com

        // comm
        $case 3:
            #y *= $x;
        $default:
            #y -= $x;
    $endswitch
}