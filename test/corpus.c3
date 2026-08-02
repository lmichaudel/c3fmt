import c3fmt::executable;
import std::io;

fn void eprint_escaped(char c)
{
    switch (c)
    {
        case '\n': io::eprint("\\n");
        case '\r': io::eprint("\\r");
        case '\t': io::eprint("\\t");
        case '\0': io::eprint("\\0");
        case ' ':  io::eprint("' '");
        default:
            if (c < 32 || c > 126)
            {
                io::eprintf("\\x%02X", (uint)c);
            }
            else
            {
                io::eprintf("'%c'", c);
            }
    }
}

macro test($name, $input_path, $solution_path, Config config = c3fmt::default_config())
{
    String raw_input = (String)file::load(mem, $input_path)!!;
    defer raw_input.free(mem);
    String input = raw_input.replace(mem, "\r", "");
    defer input.free(mem);

    String raw_solution = (String)file::load(mem, $solution_path)!!;
    defer raw_solution.free(mem);
    String solution = raw_solution.replace(mem, "\r", "").trim();
    defer solution.free(mem);

    String formatted = c3fmt::format_string(mem, input, config, check_semantic: true)!!.trim();
    defer formatted.free(mem);

    sz min_len = min(solution.len, formatted.len);

    int line = 0;
    sz line_start = 0;

    for (sz i = 0; i < min_len; ++i)
    {
        if (solution[i] != formatted[i])
        {
            sz sol_end = i;
            while (sol_end < solution.len && solution[sol_end] != '\n') sol_end++;
            String sol_line = solution[line_start..sol_end];

            sz fmt_start = i;
            while (fmt_start > 0 && formatted[fmt_start - 1] != '\n') fmt_start--;
            sz fmt_end = i;
            while (fmt_end < formatted.len && formatted[fmt_end] != '\n') fmt_end++;
            String fmt_line = formatted[fmt_start..fmt_end];

            sz col = i - line_start;

            io::eprintfn("\n[TEST FAILURE: %s] Mismatch at index %d (Line %d, Col %d):", $name, i, line + 1, col + 1);

            io::eprint("  Expected char: ");
            eprint_escaped(solution[i]);
            io::eprintfn(" (0x%02X)", (uint)solution[i]);

            io::eprint("  Got char:      ");
            eprint_escaped(formatted[i]);
            io::eprintfn(" (0x%02X)", (uint)formatted[i]);

            io::eprintfn("\n  Expected line: %s", sol_line);
            io::eprintfn("  Got line:      %s", fmt_line);

            io::eprint("                 ");
            for (sz c = 0; c < col; ++c)
            {
                io::eprint(fmt_line[c] == '\t' ? "\t" : " ");
            }
            io::eprintfn("^");

            assert(false, "Formatter output mismatch");
        }

        if (solution[i] == '\n')
        {
            line++;
            line_start = i + 1;
        }
    }

    if (solution.len != formatted.len)
    {
        io::eprintfn("\n[TEST FAILURE: %s] String length mismatch! Expected %d chars, got %d chars.", $name, solution.len, formatted.len);
        if (formatted.len < solution.len)
        {
            io::eprintfn("  Output was truncated early at index %d (Line %d).", formatted.len, line + 1);
        }
        else
        {
            io::eprintfn("  Output has extra trailing characters starting at index %d.", solution.len);
        }
        assert(false, "Formatter output length mismatch");
    }

    test::eq(formatted, solution);
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

fn void string_concat() @test {
    Config conf = c3fmt::default_config();
    conf.max_line_length = 80;
    test("string_concat", "test/corpus/string_concat.c3", "test/corpus/string_concat_f.c3", conf);
}

fn void string_concat_align() @test {
    Config conf = c3fmt::default_config();
    conf.max_line_length = 80;
    conf.align_string_concat = true;
    test("string_concat_align", "test/corpus/string_concat.c3", "test/corpus/string_concat_align_f.c3", conf);
}

fn void alignment() @test {
    Config conf = c3fmt::default_config();
    conf.max_line_length = 180;
    test("alignment", "test/corpus/alignment.c3", "test/corpus/alignment_f.c3", conf);
}

fn void alignment_wrap_stability() @test {
    test("alignment_wrap_stability", "test/corpus/alignment_wrap_stability.c3", "test/corpus/alignment_wrap_stability_f.c3");
}

fn void newline_at_eof() @test {
    String input = "fn void main() {}";

    Config conf = c3fmt::default_config();
    assert(!conf.newline_at_eof);

    String without_newline = c3fmt::format_string(mem, input, conf, check_semantic: true)!!;
    defer without_newline.free(mem);
    assert(without_newline.len > 0);
    assert(without_newline[^1] != '\n');

    conf.newline_at_eof = true;
    String with_newline = c3fmt::format_string(mem, input, conf, check_semantic: true)!!;
    defer with_newline.free(mem);
    assert(with_newline.len > 0);
    assert(with_newline[^1] == '\n');
}

fn void indent_leak() @test {
    test("indent_leak", "test/corpus/indent_leak.c3", "test/corpus/indent_leak_f.c3");
}

fn void generics() @test {
    test("generics", "test/corpus/generics.c3", "test/corpus/generics_f.c3");
}

fn void knr_braces() @test {
    Config conf = c3fmt::default_config();
    conf.brace_style = K_AND_R;
    test("knr_braces", "test/corpus/knr_braces.c3", "test/corpus/knr_braces_f.c3", conf);
}

fn void varargs() @test {
    test("varargs", "test/corpus/varargs.c3", "test/corpus/varargs_f.c3");
}

fn void comment_indent() @test {
    Config conf = c3fmt::default_config();
    conf.align_comments = true;
    test("comment_indent", "test/corpus/comment_indent.c3", "test/corpus/comment_indent_f.c3", conf);
}

fn void deep_else_if() @test {
    Config conf = c3fmt::default_config();
    conf.align_comments = true;
    test("deep_else_if", "test/corpus/deep_else_if.c3", "test/corpus/deep_else_if_f.c3", conf);
}

fn void disable() @test {
    test("disable", "test/corpus/disable.c3", "test/corpus/disable_f.c3");
}

fn void ternary_nested() @test {
    test("ternary_nested", "test/corpus/ternary_nested.c3", "test/corpus/ternary_nested_f.c3");
}

fn void trailing_comma() @test {
    test("trailing_comma", "test/corpus/trailing_comma.c3", "test/corpus/trailing_comma_f.c3");
}
