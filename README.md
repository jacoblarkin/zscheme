# zscheme

[r<sup>7</sup>rs](https://github.com/johnwcowan/r7rs-work/blob/master/R7RSHomePage.md) scheme implemetation in [zig](https://ziglang.org).

Current status: 
- r7rs lexer based on section 7.1.1 of [r7rs spec](https://github.com/johnwcowan/r7rs-spec/blob/errata/spec/r7rs.pdf)
- parser ~~with exception of `(a . b)` and `(a b c d . e)` expressions~~ (need to test `.`)
- addition of integers in a tree-walk-interpreter.

# TODO

This section is incomplete and just of list of things to implement in roughly the order I expect to implement them in.

- [x] Lexer
  - [x] Nested Comments
  - [x] Tests
    - Preliminary unit tests done. Need to write tests for `Lexer.getNextToken`.
  - [ ] Simplification?
- [x] Parser
  - [x] Cons and improper lists
    - Should be done, but need to test.
  - [ ] Tests
- [x] Tree-Walk-Interpreter
  - [x] Addition of integers
  - [ ] Simple Expressions
  - [ ] Big-Ints
  - [ ] Garbage Collector
  - [ ] Lambdas
  - [ ] Syntax-rules
  - [ ] r7rs records
  - [ ] r7rs libraries
- [ ] Bytecode Interpreter
- [ ] Native compiler?
