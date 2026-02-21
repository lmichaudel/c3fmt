<p align="center">
  <img src=".github/c3fmt_logo.png" alt="logo banner" width="40%">
</p>

#

<p align="center">
  <img src="https://github.com/lmichaudel/c3fmt/actions/workflows/actions.yml/badge.svg">
  <img src="https://img.shields.io/badge/c3-v7.9-blue">
  <img src="https://img.shields.io/badge/license-MIT-blue">
</p>

A customizable code formatter for the C3 language, written in C3.

Check the [c3fmt-vscode](https://marketplace.visualstudio.com/items?itemName=lmichaudel.c3fmt) extension to use it inside VS Code.

## Usage

Usage:
```bash
c3fmt [<options>] <files>
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
```

## Configuration

`c3fmt` will try to find a `.c3fmt` format inside the working directory. You can also
pass your own path to `c3fmt`, or force the default configuration.

You can look at [.c3fmt](.c3fmt) for the default configuration.
## Building

Run `c3c build` to build `c3fmt`.

The only dependency is the [tree-sitter](https://github.com/tree-sitter/tree-sitter) sdk.

## Planned features / wishlist

- Code wrapping (current breaks with nested constructions).
- Align consecutive assignments / declaration / comments.
- Wrapping indent option. (ContinuationIndentWidth)
- Align wrapped items.
- Space before <...> options.
- Import sorting
- Pointer alignment ? (kind of a pain and I think right alignment is heretic)

## Tests

There are two tests for the moment :

- Corpus takes a `.c3` source file, format it and compare it the same file with a `_f.c3` format corresponding to the expected output.
- Stdlib formats every file from the C3 standard library, then verifiy it still compiles with the same semantic. (For the moment it won't automatically try to compile it, but you can go to `test/stdlib` and run `c3c build`)

Each test checks that the syntax tree of the formatted code is the same as the original one.
