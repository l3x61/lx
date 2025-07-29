# lya

Experimental functional language written in Zig.

## ToDo

lexer
- [x] utf-8 support
interpreter
- [x] environment
- [x] closures
repl
- [ ] help/usage
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
- [ ] comments
- [ ] let expression
- [ ] recursive let expression
- [ ] if-then-else expression
- [ ] garbage collector
- [ ] type system
syntax sugar
- [ ] arguments
- [ ] bindings
error messages
- [ ] which line and what token

## Grammar

```py
program
    = expression* EOF
expression
    = abstraction
    | application
abstraction
    = ('\\' | 'λ') IDENTIFIER '.' expression
application
    = primary primary*
primary
    = NUMBER
    | IDENTIFIER
    | abstraction
    | '(' expression ')'

NUMBER
    = # whatever std.fmt.parseFloat accepts
IDENTIFIER
    = # anything that is not '(', ')', '\\', or 'λ'
WHITESPACE
    = # ' ', '\t', '\f', '\r', '\n', NEL (U+0085), NBSP (U+00A0)
```

## Dependencies

- `readline` [GNU Readline](https://tiswww.cwru.edu/php/chet/readline/rltop.html)

## References
