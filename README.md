# c3fmt

A customizable code formatter for the C3 language, written in C3.

## About the parser 

C3fmt use tree-sitter to generate a tree that is then walked down.

For the moment it's very experimental and doesn't even support the whole language.
If c3fmt doesn't know how to format a bit of code, it will not touch it.

## Test

The final goal is obviously to support the whole grammar of c3. 

There are two tests for the moment :

- Corpus takes a `.c3` source file, format it and compare it the same file with a `.c3f` format corresponding to the expected output.
- Stdlib formats every file from the C3 standard library, then verifiy it still compiles with the same semantic.