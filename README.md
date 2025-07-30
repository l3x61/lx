# ly

Experimental functional language written in Zig.

## Language Reference

### Literals

#### Numbers

```
3
3.1415
3.1415E+00
```

### Variables

A variable is a name that refers to a value in the environment.

For a variable name to be valid, it should not match to an OPERATOR or a KEYWORD.

```py
let # invalid, keyword
=   # invalid, operator

letlet # valid name
====== # also valid
```

### Function Abstractions

A function abstraction creates an anonymous function.

It takes the form: `λx. x` or `\x. x`.

The first `x` represents the function parameter, the second `x` the function body.

### Function Applications

A function application applies one expression to another.

The application `f x` applies `f` to `x`.

Applications associate left-to-right: `f a b c` is interpreted as `((f a) b) c`.

### Let Expressions

A let expression binds a value to a name for a given expression.

The expression `let one = 1 in one` binds `1` to `one` for the expression after the _in_.

Let expressions may be chained to create multiple bindings

```
let true = λa. λb. a in
let false = λa. λb. b in
let AND = λp. λq. p q p in
    AND true true
```

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

language

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
