<p align="center">
  <img src=".github/c3fmt_logo.png" alt="logo banner" width="40%">
</p>

#

<p align="center">
  <img src="https://github.com/lmichaudel/c3fmt/actions/workflows/main.yml/badge.svg">
  <img src="https://img.shields.io/badge/c3-v8.2-blue">
  <img src="https://img.shields.io/badge/license-MIT-blue">
</p>

A customizable code formatter for the C3 language, written in C3.

## Usage

Usage:
```bash
c3fmt [<options>] <files/directories>
```
Options:
```
-h, --help       - Show this help.
-v, --version    - Show current version.
--in-place       - Format files in place.
--stdin          - Read input from stdin.
--stdout         - Output result to stdout.
--config=<path>  - Specify a config file.
--default        - Force default config.
--check          - Finish with error if files are not formatted.
```

### Ignoring sections
Use comments to prevent the formatter from modifying a block of code:
```c3
// c3fmt off
int x = 3;
bool y = false;
// c3fmt on
```

## Configuration

`c3fmt` will try to find a `.c3fmt` configuration file inside the working directory. You can also pass your own path to `c3fmt` using the `--config` flag, or force the default configuration with `--default`.

You can look at [.c3fmt](.c3fmt) for the default configuration.

### Available Options

| Key | Description | Default |
| --- | --- | --- |
| `use_tabs` | Use tabs for indentation. | `true` |
| `tab_size` | The width of a tab character. | `4` |
| `indent_width` | The number of spaces to use for indentation (if `use_tabs` is false). | `4` |
| `max_blank_line_between_statements` | Maximum number of blank lines to preserve between statements. | `2` |
| `max_line_length` | Maximum line length before wrapping. | `120` |
| `brace_style` | The brace style to use: `ALLMAN` or `K&R`. | `ALLMAN` |
| `else_on_newline` | Whether to put `else` on a new line. | `true` |
| `newline_at_eof` | Ensure formatted output ends with a newline. | `false` |
| `spaces_before_trailing_comment` | The number of space inserted before trailing comments | `1` |
| `align_assignments` | Align `=` and `=>` in consecutive declarations/assignments. | `true` |
| `align_comments` | Align trailing comments in consecutive lines. | `true` |
| `align_string_concat` | Align wrapped adjacent string literals under the first literal's column (otherwise indent one level). | `false` |

## Building

Building requires the [C3 compiler](https://c3-lang.org/) and the [tree-sitter](https://github.com/tree-sitter/tree-sitter) SDK library. You can either use a globally installed tree-sitter library, or build a local copy easily using the project's build scripts.

### 1. (Recommended) Building with a local tree-sitter library

To avoid installing tree-sitter globally, you can clone and build a local static library directly using our helper script (requires `git`, `cmake`, and a C compiler, running inside a Bash-compatible environment like Linux, macOS, or Git Bash on Windows):

```bash
# 1. Build the local tree-sitter library (outputs to build/ts-lib/lib)
c3c build tree-sitter --trust=full

# 2. Build c3fmt (it will automatically find and link the local library)
c3c build
```

### 2. Building with a globally installed tree-sitter library

If you already have `tree-sitter` installed globally on your system, you can build the executable directly:

```bash
c3c build
```

If the library is not in your system's default search path, specify it using the `-L` flag:

```bash
c3c build -L /path/to/tree-sitter/lib
```

The compiled binary will be located in `build/c3fmt`.

### Building Statically (Linux with musl)

To build a fully static version of `c3fmt` linked against musl (useful for standalone Linux distribution):

```bash
# 1. Build local tree-sitter
c3c build tree-sitter --trust=full

# 2. Build the static binary
c3c build c3fmt-static
```

### Updating Sources

You can keep the project dependencies and test data up-to-date using the built-in `prepare` targets:

*   **Tree-sitter Grammar:** Update the C3 grammar parser from upstream.
    ```bash
    c3c build update-grammar --trust=full
    ```
*   **Standard Library:** Sync `test/stdlib/src` with the latest C3 standard library for stability testing.
    ```bash
    c3c build update-stdlib --trust=full
    ```

## Tests

Run all tests using the C3 compiler:
```bash
c3c test
```

Just like with the build command, if `tree-sitter` is not in your search path, use the `-L` flag:
```bash
c3c test -L /path/to/tree-sitter/lib
```

The test suite includes:
- **Corpus**: Compares formatted output against expected `_f.c3` files.
- **Stability**: Ensures that formatting already-formatted code produces no changes (idempotency).
- **Stdlib**: Formats the entire C3 standard library and verifies that it still compiles and maintains the same syntax tree.

## Vendored libraries

- `src/opt.c3`: A vendored copy of [getopt.c3l](https://github.com/NotsoanoNimus/getopt.c3l).
- `lib/tree_sitter.c3l`: C3 bindings for the core tree-sitter SDK.
- `lib/tree_sitter_c3.c3l`: C3 grammar bindings for tree-sitter.

## Planned features / wishlist

- Wrapping indent option (ContinuationIndentWidth).
- Import sorting.
- Pointer alignment calibration.

## Known issues

*(none yet)*
