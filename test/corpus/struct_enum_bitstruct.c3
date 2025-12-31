struct 
    MyData {
    char* name;  
    String open,  close;    

    struct other {
        int value; 
        int status;
    }
    
    struct
    {
        int value;
        int status;
    }

    int in_between;

    union {
        Person* person;
        Company* company;
    }

    union  either
    {
        int this;
        bool or;
        char* that;
    }
}

enum State
: int
{
    WAITING, RUNNING, TERMINATED
}

enum State : int (String description) {
    WAITING = "waiting",
    RUNNING = "running",
    TERMINATED = "ended"
}

enum State : int (String desc, bool active, Position pos)
{
    WAITING    = { "waiting", false, { 1, 2} },
    RUNNING    = { "running", true,  {12,22} },
    TERMINATED = { "ended",   false, { 0, 0} }
}

enum KeyCode : const CInt
{
    UNKNOWN=0,RETURN = 13, ESCAPE = 27,
    BACKSPACE = 8,
    TAB = 9,
    SPACE =  32,
    EXCLAIM,
    QUOTEDBL,
    HASH
}

enum ConstInline : const inline String
{
    A =  "Hello",
    B = "World"
}

State current_state 
    = WAITING;