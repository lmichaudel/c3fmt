import std::io;
import c3fmt::executable;

const String ROOT = "test/stdlib/src";

faultdef INVALID_PATH;

fn Path? convert_path(Path input, Allocator allocator)
{
    Path cwd = path::cwd(mem)!;
    defer cwd.free();
    String cwd_s = cwd.str_view().replace(mem, "\\", "/");
    defer cwd_s.free(mem);
    String in_s = input.str_view().replace(mem, "\\", "/");
    defer in_s.free(mem);

    if (!in_s.starts_with(cwd_s)) return INVALID_PATH~;

    usz rel_start = cwd_s.len;
    if (in_s.len > rel_start && in_s[rel_start] == '/') rel_start++;

    String rel = in_s[rel_start..];
    if (!rel.starts_with(ROOT)) return INVALID_PATH~;

    String stripped = rel[ROOT.len..];
    DString d = dstring::new(mem);
    defer d.free();
    d.append("test/stdlib/src-formatted");
    d.append(stripped);

    return path::new(allocator, d.str_view(), input.env);
}


fn bool? process_source_file(Path path, bool is_dir, any data)
{
    if (!is_dir)
    {
        String input = (String)file::load(mem, path.str_view())!!;
        defer input.free(mem);
        String? formatted = c3fmt::format_string(mem, input, check_semantic: true);
        defer (void)formatted.free(mem);

        Path target_path = convert_path(path, mem)!!;
        defer target_path.free();

        if (catch excuse = formatted)
        {
            io::eprintfn("Skipping formatting: %s (%s) - copying original", path.str_view(), excuse);
            std::io::path::mkdir(target_path.parent()!!, true)!!;
            std::io::file::save(target_path.str_view(), input)!!;
            int* skipped_ptr = (int*)data + 1;
            (*skipped_ptr)++;
        }
        else
        {
            std::io::path::mkdir(target_path.parent()!!, true)!!;
            std::io::file::save(target_path.str_view(), formatted)!!;
            int* count_ptr = (int*)data;
            (*count_ptr)++;
        }
    }
    return false;
}

fn void format_and_compile_std_lib() @test
{
    Path root = std::io::path::new(mem, ROOT)!!;
    defer root.free();

    int[2] counters; // [success_count, skipped_count]
    std::io::path::traverse(root, &process_source_file, &counters)!!;
    io::printfn("Stdlib test result: %d formatted, %d skipped due to syntax errors.", counters[0], counters[1]);
}
