# Lambda eXpression language

Experimental functional language written in Zig.

## Syntax Grammar

```py
program
    = expression* EOF
expression
    = let_in
    | abstraction
    | application
let_in
    = 'let' IDENTIFIER '=' expression 'in' expression
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
KEYWORD
    = '\\' | 'λ' | 'let' | 'in'
OPERATOR
    = '(' | ')' | '.' | '='
IDENTIFIER
    = # anything that is not and OPERATOR, KEYWORD, or WHITESPACE
WHITESPACE
    = # ' ', '\t', '\f', '\r', '\n', NEL (U+0085), NBSP (U+00A0)
```

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
