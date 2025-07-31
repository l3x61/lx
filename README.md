# Lambda eXpression language

Experimental functional language written in Zig.

## Dependencies

- `readline` [GNU Readline](https://tiswww.cwru.edu/php/chet/readline/rltop.html)

## ToDo

- [ ] move to docs/

lexer

- [x] utf-8 support

interpreter

- [x] environment
- [x] closures

repl

- [ ] help/usage
- [ ] implement own readline (with syntax highlighting)
- [ ] reuse result in new expression
- [ ] syntax highlighting

types

- [x] null
- [ ] boolean
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

- [ ] define expression
- [ ] comments
- [x] let expression
- [ ] recursive let expression
- [ ] if-then-else expression
- [ ] garbage collector
- [ ] type system

syntax sugar

- [ ] arguments
- [ ] bindings

error messages

- [ ] which line and what token
