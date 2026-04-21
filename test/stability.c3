import std;
import c3fmt;

const String ROOT = "test/stdlib/src";

faultdef INVALID_PATH;

struct Results
{
    Atomic{int} formatted;
    Atomic{int} skipped;
	Atomic{int} errors;
}

struct Context
{
    List{String}* paths;
    Atomic{int} next_index;
    Results* results;
}

Context g_ctx;


fn void stability_worker_task(any[] args) => @pool_init(mem, 1024 * 1024)
{
    while (true)
    {
        int i = g_ctx.next_index.add(1);
        if (i >= (int)g_ctx.paths.len()) break;

        String path_s = (*g_ctx.paths)[(usz)i];

		Path path = path::new(mem, path_s)!!;
		String input = (String)file::load(mem, path_s)!!;
		String? formatted = c3fmt::format_string(mem, input, check_semantic: true);

		if (catch excuse = formatted)
		{
			io::eprintfn("Skipping: %s (%s)", path_s, excuse);
			g_ctx.results.skipped.add(1);
		}
		else
		{
			String? reformatted = c3fmt::format_string(mem, formatted, check_semantic: true);

			if (catch excuse2 = reformatted)
			{
				io::eprintfn("Error during second format of %s: %s", path_s, excuse2);
				//unreachable();
				g_ctx.results.errors.add(1);
			}

			if (catch excuse3 = (formatted != reformatted))
			{
				io::eprintfn("Stability failure: %s, %s", path_s, excuse3);
				//unreachable();
				g_ctx.results.errors.add(1);
			}
			g_ctx.results.formatted.add(1);
		}
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

fn void stability() @test
{
    Path root = path::new(mem, ROOT)!!;
    defer root.free();

    List{String} paths;
    paths.init(mem);
    defer
    {
        foreach (p : paths) p.free(mem);
        paths.free();
    }

    path::traverse(root, &collect_paths, &paths)!!;

    Results results;
    //results.formatted.store(0);
    //results.skipped.store(0);


    g_ctx.paths = &paths;
    g_ctx.next_index.store(0);
    g_ctx.results = &results;

    int num_threads = os::num_cpu();
    FixedThreadPool pool;
    pool.init(num_threads, num_threads)!!;
    defer pool.stop_and_destroy();

    for (usz i = 0; i < num_threads; i++)
    {
        pool.push(&stability_worker_task)!!;
    }

    pool.join();

    defer io::printfn("Stability test result: %d formatted, %d skipped due to syntax errors, %d format errors",
		results.formatted.load(), results.skipped.load(), results.errors.load());
}
