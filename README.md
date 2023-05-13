# zscheme

[r<sup>7</sup>rs](r7rs.org) scheme implemetation in [zig](ziglang.org).

# TODO

This section is incomplete and just of list of things to implement in roughly the order I expect to implement them in.

- [x] Lexer
  - [ ] Nested Comments
- [x] Parser
- [ ] Interpreter
  - [ ] Simple Expressions
  - [ ] Lambdas
  - [ ] Syntax-rules

Not listed above is fixing all the memory leaks currently in the prototype interpreter.
Switching to a garbage collector for the main allocator should help with this, but probably isn't the optimal solution.
