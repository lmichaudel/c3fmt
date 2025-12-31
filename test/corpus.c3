import c3fmt::executable;
import std::io;

macro test($name, $input_path, $solution_path) {
    String input = c3fmt::executable::read_file($input_path)!!;
    String solution = c3fmt::executable::read_file($solution_path)!!;
    String formatted = c3fmt::format_string(mem, input, check_semantic: true)!!;

    int len = solution.len;
    if(formatted.len != len) {
        len = (int)min(formatted.len, len);
    }

    int line = 0;
    for(usz i = 0; i < len; ++i) {
        if(solution[i] != formatted[i]) {
            io::eprintfn("For context, here is the output :");
            io::eprintfn("%s", formatted);
            io::eprintfn("Character mismatch '%c' vs '%c' on line %s.", solution[i], formatted[i], line + 1);

            input.free(mem);
            solution.free(mem);
            formatted.free(mem);

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

fn void struct_enum_bitstruct() @test {
    test("struct_enum_bitstruct", "test/corpus/struct_enum_bitstruct.c3", "test/corpus/struct_enum_bitstruct_f.c3");
}

fn void if_statements() @test {
    test("if_statements", "test/corpus/if_statements.c3", "test/corpus/if_statements_f.c3");
}

fn void for_statements() @test {
    test("for_statements", "test/corpus/for_statements.c3", "test/corpus/for_statements_f.c3");
}

fn void switch_statements() @test {
    test("switch_statements", "test/corpus/switch_statements.c3", "test/corpus/switch_statements_f.c3");
}

// fn void wrapping() @test {
//     test("wrapping", "test/corpus/wrapping.c3", "test/corpus/wrapping_f.c3");
// }