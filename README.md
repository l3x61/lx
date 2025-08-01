# Lambda eXpression language

Experimental functional language written in Zig.

## Dependencies

- `readline` [GNU Readline](https://tiswww.cwru.edu/php/chet/readline/rltop.html)

## ToDo


lexer

- [x] utf-8 support

interpreter

- [x] environment
- [x] closures

repl

- [ ] help/usage
- [ ] implement own readline (with syntax highlighting)
- [ ] reuse result in new expression
- [x] exit
- [x] env
- [ ] syntax highlighting

types

- [x] null
- [x] boolean
- [x] number
- [ ] string
- [ ] list
- [ ] table
- [x] function

operators

- [ ] arithmetic
- [ ] logic
- [ ] relational

language

- [ ] comments
- [x] let expression
- [x] let-in expression
- [ ] recursive let expression
- [x] if-then-else expression
- [ ] garbage collector
- [ ] type system

syntax sugar

- [ ] arguments
- [ ] bindings

error messages

- [ ] which line and what token
