import c3fmt::executable;
import std::io; 

macro test($name, $input_path, $solution_path) {
    String input = c3fmt::executable::read_file($input_path)!!;
    String solution = c3fmt::executable::read_file($solution_path)!!;
    String formatted = c3fmt::format_string(mem, input)!!;


    int len = solution.len; 
    if(formatted.len != len) {
        len = (int)min(formatted.len, len);
    }

    int line = 0;
    for(usz i = 0; i < len; ++i) {
        if(solution[i] != formatted[i]) {
            io::eprintfn("Character mismatch '%c' vs '%c' on line %s.", solution[i], formatted[i], line);
            input.free(mem);
            solution.free(mem);
            formatted.free(mem);

            io::eprintfn("For context, here is the output :");
            io::eprintfn("%s", formatted);
            assert(false);
        }

        if(solution[i] == '\n') {
            line++;
        }
    }

    assert(formatted == solution, $name +++ " test failed!"); 

    input.free(mem); 
    solution.free(mem);
    formatted.free(mem);
}

fn void corpus_struct () @test {
    test("struct", "test/corpus/simple/struct.c3", "test/corpus/simple/struct.c3f");
}