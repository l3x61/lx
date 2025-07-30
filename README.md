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

## Language Concepts

### Name

A name (or identifier) is a sybolic label used to refer a value.
Names are bound to values within an enviroment.

### Value

A value is the result of evaluating an expression.
Values can be numbers or functions (for now).

### Variable

    TODO

### Lifetime

    TODO

### Environment

An environment is a mapping from names to values.

Environments can be chained, where each environment may have a parent. When looking up a name,\
the current environment is checked first, followed by its parent, and so on.

New environments are created by either:

- Applying a function to an argument `(\x. x) 1`
  Here an environment with the mapping `x = 1` is created for the body.
- Using a let expression `let f = \x. x in f 1`
  Here an environment with the mapping `f = \x. x` is created for the body.

### Bindings

A binding associates a name with a value within an environment.

In the expression `let f = \x. x in f 1` two bindings occur:

1. The name `f` is bound to `\x. x` for the expression `f 1`.
2. When `f` is applied to `1`, the argument `1` is bound to the parameter `x` within `f`.

### Shadowing

Shadowing occurs when an inner binding uses the same name as an outer one.

```
let x = 1 in
let x = 2 in
    x
```

Here the inner `x = 2` shadows the outer `x = 1` one. The result of this expression is `2`\
because only the inner binding is visible in the innermost scope.

### Closures

A closure is a function along with the enviroment in which it was defined.

```
(\x. \y. x) 1 2
```

Here the inner function `\y. x` captures the environment of the outer one, enabling it to access the variable `x`.

### Scope

A region in which a variable is valid. TODO

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
