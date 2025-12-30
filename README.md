<h1 align="center">c3fmt</h1>



<p align="center">
  <img src="https://github.com/lmichaudel/c3fmt/actions/workflows/actions.yml/badge.svg">
  <img src="https://img.shields.io/badge/c3-v7.7-blue">
</p>

A customizable code formatter for the C3 language, written in C3.

## About the parser

c3fmt use tree-sitter to generate a tree that is then walked down.

For the moment it's very experimental and doesn't even support the whole language.
If c3fmt doesn't know how to format a bit of code, it will not touch it. Please report any
of these incident, I tested the formatted against the whole std but maybe missed some grammar points.

c3fmt won't change any non whitespace character in your code, EXCEPT : 
- Last comma inside enum definition : 
```c
enum MyEnum {
    OPTION_ONE,
    OPTION_TWO,
}
```
would become
```c
enum MyEnum {
    OPTION_ONE,
    OPTION_TWO
}
```
- Line comments between a statement and its scope :
```c
if (a >= 0) // Check if a >= 0
{ ... }
```
would become
```c
if (a >= 0) /* Check if a >= 0 */
{ ... }
```
or
```c
if (a >= 0) /* Check if a >= 0 */ {
    ...
}
```
Depending on brace style
## Usage

```bash
c3fmt <source_file>
```

## Test

The final goal is obviously to support the whole grammar of c3.

There are two tests for the moment :

- Corpus takes a `.c3` source file, format it and compare it the same file with a `_f.c3` format corresponding to the expected output.
- Stdlib formats every file from the C3 standard library, then verifiy it still compiles with the same semantic. (For the moment it won't automatically try to compile it, but you can go to `test/stdlib` and run `c3c build`)