import std::io;
import c3fmt::executable;

const String ROOT = "test/stdlib";

fn bool? process_source_file (Path path, bool is_dir, any data) {
    if(!is_dir) {
        //io::printfn("Processing %s", path);
        String input = c3fmt::executable::read_file(path.str_view())!!;
        String formatted = c3fmt::format_string(mem, input)!!;
        int* ptr = (int*) data;
        (*ptr)++;
    }
    return false;
}
fn void recurse_format() @test {
    Path? path = std::io::path::new(mem, ROOT);
    defer (void)path.free();
    if(catch excuse = path) {
        return;
    }

    int formatted_file_count;
    std::io::path::traverse(path, &process_source_file, &formatted_file_count)!!;
    io::printfn("Formatted %s files.", formatted_file_count);
    assert(false);
}