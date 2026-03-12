import c3fmt::executable;
import std::io;

macro test($name, $input_path, $solution_path, Config config = c3fmt::default_config())
{
    String raw_input = (String)file::load(mem, $input_path)!!;
    defer raw_input.free(mem);
    String input = raw_input.replace(mem, "\r", "");
    defer input.free(mem);

    String raw_solution = (String)file::load(mem, $solution_path)!!;
    defer raw_solution.free(mem);
    String solution = raw_solution.replace(mem, "\r", "");
    defer solution.free(mem);

    String formatted = c3fmt::format_string(mem, input, config, check_semantic: true)!!;
    defer formatted.free(mem);

    int len = solution.len;
    if (formatted.len != len) len = (int)min(formatted.len, len);

    int line = 0;
    for (usz i = 0; i < len; ++i)
    {
        if (solution[i] != formatted[i])
        {
            io::eprintfn("For context, here is the output :");
            io::eprintfn("%s", formatted);
            io::eprintfn("Character mismatch expected:'%c' got:'%c' on line %d.", solution[i], formatted[i], line + 1);
            assert(false);
        }
        if (solution[i] == '\n') line++;
    }

    assert(formatted == solution, $name +++ " test failed!");
}


fn void struct_enum_bitstruct() @test {
    test("struct_enum_bitstruct", "test/corpus/struct_enum_bitstruct.c3", "test/corpus/struct_enum_bitstruct_f.c3");
}

fn void struct_nested_initializers() @test {
    test("struct_nested_initializers", "test/corpus/struct_nested_initializers.c3", "test/corpus/struct_nested_initializers_f.c3");
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

fn void wrapping() @test {
    Config conf = c3fmt::default_config();
    conf.max_line_length = 80;
    test("wrapping", "test/corpus/wrapping.c3", "test/corpus/wrapping_f.c3", conf);
}

fn void comments() @test {
    Config conf = c3fmt::default_config();
    conf.max_line_length = 80;
    test("comments", "test/corpus/comments.c3", "test/corpus/comments_f.c3", conf);
}