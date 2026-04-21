<p align="center">
  <img src=".github/c3fmt_logo.png" alt="logo banner" width="40%">
</p>

#

<p align="center">
  <img src="https://github.com/lmichaudel/c3fmt/actions/workflows/main.yml/badge.svg">
  <img src="https://img.shields.io/badge/c3-v7.11-blue">
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
| `align_assignments` | Align `=` and `=>` in consecutive declarations/assignments. | `true` |
| `align_comments` | Align trailing comments in consecutive lines. | `true` |
## Building

Building requires the [C3 compiler](https://c3-lang.org/) and the [tree-sitter](https://github.com/tree-sitter/tree-sitter) SDK library.

To build the executable:
```bash
c3c build
```
The binary will be located in `build/c3fmt`.

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

