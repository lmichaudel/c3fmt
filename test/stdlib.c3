import std;
import c3fmt;

const String ROOT = "test/stdlib/src";

faultdef INVALID_PATH;

struct Results
{
    Atomic{int} formatted;
    Atomic{int} skipped;
}

fn Path? convert_path(Path input, String cwd_s, Allocator allocator)
{
    String in_s = input.str_view().replace(allocator, "\\", "/");

    if (!in_s.starts_with(cwd_s)) return INVALID_PATH~;

    usz rel_start = cwd_s.len;
    if (in_s.len > rel_start && in_s[rel_start] == '/') rel_start++;

    String rel = in_s[rel_start..];
    if (!rel.starts_with(ROOT)) return INVALID_PATH~;

    String stripped = rel[ROOT.len..];
    DString d = dstring::new(allocator);
    d.append("test/stdlib/src-formatted");
    d.append(stripped);

    return path::new(allocator, d.str_view(), input.env);
}

struct Context
{
    List{String}* paths;
    Atomic{int} next_index;
    String cwd_s;
    Results* results;
}

Context g_ctx;


fn void stdlib_worker_task(any[] args)
{
    while (true)
    {
        int i = g_ctx.next_index.add(1);
        if (i >= (int)g_ctx.paths.len()) break;

        String path_s = (*g_ctx.paths)[(usz)i];

        @pool_init(mem, 1024 * 1024)
        {
            Path path = path::new(tmem, path_s)!!;
            String input = (String)file::load(tmem, path_s)!!;
            String? formatted = c3fmt::format_string(tmem, input, check_semantic: true);
            Path target_path = convert_path(path, g_ctx.cwd_s, tmem)!!;

            if (catch excuse = formatted)
            {
                io::eprintfn("Skipping formatting: %s (%s) - copying original", path_s, excuse);
                (void)path::mkdir(target_path.parent()!!, true);
                (void)file::save(target_path.str_view(), input);
                g_ctx.results.skipped.add(1);
            }
            else
            {
                (void)path::mkdir(target_path.parent()!!, true);
                (void)file::save(target_path.str_view(), formatted);
                g_ctx.results.formatted.add(1);
            }
        };
    }
}

fn bool? collect_paths(Path path, bool is_dir, any data)
{
    if (!is_dir)
    {
        List{String}* list = (List{String}*)data;
        list.push(path.str_view().copy(mem));
    }
    return false;
}

fn void format_and_compile_std_lib() @test
{
    Path root = path::new(mem, ROOT)!!;
    defer root.free();

    Path cwd = path::cwd(mem)!!;
    defer cwd.free();
    String cwd_s = cwd.str_view().replace(mem, "\\", "/");
    defer cwd_s.free(mem);

    List{String} paths;
    paths.init(mem);
    defer
    {
        foreach (p : paths) p.free(mem);
        paths.free();
    }

    path::traverse(root, &collect_paths, &paths)!!;

    Results results;
    results.formatted.store(0);
    results.skipped.store(0);

    g_ctx.paths = &paths;
    g_ctx.next_index.store(0);
    g_ctx.cwd_s = cwd_s;
    g_ctx.results = &results;

    int num_threads = os::num_cpu();
    FixedThreadPool pool;
    pool.init(num_threads, num_threads)!!;
    defer pool.stop_and_destroy();

    for (usz i = 0; i < num_threads; i++)
    {
        pool.push(&stdlib_worker_task)!!;
    }

    pool.join();

    io::printfn("Stdlib    test result: %d formatted, %d skipped due to syntax errors.", results.formatted.load(), results.skipped.load());
}
