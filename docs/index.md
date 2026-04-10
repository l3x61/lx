# Lx Specification

::: info 
This specification adopts a structure similar to the [Go Programming Language
Specification](https://go.dev/ref/spec#Notation), particularly in its use of
formal notation and section organization. 
:::


## Overview

Lx is a small expression-oriented functional language centered on unified
control flow through pattern-based function application. Instead of using
separate constructs for function definition, branching, and iteration, Lx
expresses control through ordered pattern branches and recursion.

::: info Example
```lx
let fizzbuzz = (n) {
    ? n % 15 == 0 => print("FizzBuzz")
    ? n % 3 == 0 => print("Fizz")
    ? n % 5 == 0 => print("Buzz")
    => print(n)
};

let loop = (i, max) {
    i, max ? i > max => print("Done.")
    => {
        fizzbuzz(i);
        loop(i + 1, max)
    }
};

loop(1, 15)
```
:::

## Notation

The syntax is specified using a Wirth-style syntax notation.

```wsn
syntax      = { production } .
production  = name "=" expression "." .
expression  = term { "|" term } .
term        = factor { factor } .
factor      = name | token | group | option | repetition .
group       = "(" expression ")" .
option      = "[" expression "]" .
repetition  = "{" expression "}" .

name  = letter { letter | digit | "-" } .
token = '"' { character } '"' | "'" { character } "'" .
```

In this meta-notation:

- `character` denotes any Unicode code point.
- `letter` denotes any Unicode code point classified as a letter.
- `digit` denotes any ASCII digit, that is, one of `0` through `9`.

## Lexical Elements

### Comments

Comments begin with `#` and continue until a newline or the end of the input.

::: info Example
```lx
# this is a comment
```
:::

### Identifiers

Identifiers begin with a letter or underscore and may continue with letters,
digits, or underscores.

::: info Example
```lx
value
_12x34
```
:::

### Literals

Lx has numeric, string, and boolean literals. Numeric literals may be written
as integers or decimal floating-point values.

::: info Example
```lx
1234
3.14
"lx"
true
false
```
:::

## Grammar

```wsn
program = expression EOF .

expression
    = let-binding ";" expression
    | non-binding [ ";" expression ]
    .

non-binding
    = function
    | block
    | binary
    .

let-binding = "let" pattern "=" non-binding .

function = "(" [ parameters ] ")" "{" function-body "}" .
parameters = identifier { "," identifier } .
function-body = expression | branches .

branches = branch { newline branch } .
branch
    = patterns [ "?" expression ] "=>" expression
    | "?" expression "=>" expression
    | "=>" expression
    .
patterns = pattern { "," pattern } .

binary = disjunction .
disjunction = conjunction { "||" conjunction } .
conjunction = comparison { "&&" comparison } .
comparison = concat { ("==" | "!=" | "<" | ">" | "<=" | ">=") concat } .
concat = addition [ "++" concat ] .
addition = multiplication { ("+" | "-") multiplication } .
multiplication = unary { ("*" | "/" | "%") unary } .
unary = [ "-" | "!" ] application .

application = primary { "(" [ arguments ] ")" } .
arguments = expression { "," expression } .

primary
    = literal
    | identifier
    | list
    | range
    | block
    | function
    | "(" expression ")"
    .

list = "[" [ list-items ] "]" .
list-items = spread | expression { "," expression } [ "," spread ] .
spread = "..." expression .

range = "[" expression ".." expression "]" .
block = "{" expression "}" .

pattern
    = "_"
    | literal
    | identifier
    | "[" [ pattern-items ] "]"
    | "(" pattern ")"
    .

pattern-items = spread-pattern | pattern { "," pattern } [ "," spread-pattern ] .
spread-pattern = "..." pattern .

literal = number | string | boolean .
boolean = "true" | "false" .
number = digit { digit } [ "." digit { digit } ] .
string = '"' { character } '"' .
identifier = ( letter | "_" ) { letter | digit | "_" } .
```

## Program

```wsn
program = expression EOF .
```

A program evaluates a single expression followed by the end of the file.

## Expressions

Lx is expression-oriented. Expressions may be sequenced with `;`, which
associates to the right.

```wsn
expression
    = let-binding ";" expression
    | non-binding [ ";" expression ]
    .

non-binding
    = function
    | block
    | binary
    .
```

This form expresses sequencing by chaining bindings and non-binding expressions.

## Bindings

```wsn
let-binding = "let" pattern "=" non-binding .
```

A binding evaluates the right-hand side, matches the result against the
pattern, and extends the environment for the following expression. Bindings are
immutable.

::: info Example
```lx
let answer = 42;
answer
```
:::

## Functions

```wsn
function = "(" [ parameters ] ")" "{" function-body "}" .
parameters = identifier { "," identifier } .
function-body = expression | branches .
```

Function values are anonymous. A named function is introduced by binding a
function value. Applications always use parentheses.

In a function body, branches are separated by line breaks. A function body may
also consist of a single expression instead of a branch list.

::: info Example
```lx
let add = (x, y) { x + y };
add(1, 2)
```
:::

A single-expression body is shorthand for a function with one unconditional
branch.

::: info Example
```lx
(x, y) { x + y }
```

behaves like:

```lx
(x, y) { x, y => x + y }
```
:::

## Branches

```wsn
branches = branch { newline branch } .
branch
    = patterns [ "?" expression ] "=>" expression
    | "?" expression "=>" expression
    | "=>" expression
    .
patterns = pattern { "," pattern } .
```

A branch consists of:

- one pattern per argument
- an optional guard
- a result expression

If a branch begins with `?`, the function parameters are reused implicitly as
the branch patterns. If a branch begins with `=>`, it is an unconditional
fallback branch over the current parameters.

When a function with a branch body is applied, branches are considered from top
to bottom. The first branch whose patterns match the arguments and whose guard
evaluates to `true` is selected. If no branch is selected, evaluation halts
with a runtime error.

::: info Example
```lx
let abs = (n) {
    ? n >= 0 => n
    => -n
};

abs(-5)
```
:::

## Patterns

```wsn
pattern
    = "_"
    | literal
    | identifier
    | "[" [ pattern-items ] "]"
    | "(" pattern ")"
    .
```

Patterns are used in bindings and branches.

- `_` matches any value and binds nothing.
- A literal matches an equal literal value.
- An identifier matches any value and binds it.
- A list pattern matches structurally.
- A spread pattern `...p` matches the remainder of a list.

::: info Example
```lx
let head = (xs) {
    [x, ..._] => x
    [] => "empty"
};

head([10, 20, 30])
```
:::

## Blocks

```wsn
block = "{" expression "}" .
```

A block groups a local expression sequence and evaluates to the value of its
final expression.

::: info Example
```lx
{
    let square = (x) { x * x };
    let y = 4;
    square(y)
}
```
:::

## Lists and Ranges

```wsn
list = "[" [ list-items ] "]" .
list-items = spread | expression { "," expression } [ "," spread ] .
spread = "..." expression .

range = "[" expression ".." expression "]" .
```

Lists are written with brackets. Spread syntax appends or matches the remainder
of a list.

A range expression `[start..end]` evaluates to a list of numbers from `start`
to `end`, inclusive. In the current design, both bounds are intended to be
integral numeric values.

In an expression such as `[0, ...xs]`, the spread expression contributes the
elements of the list value produced by `xs` to the surrounding list literal. In
a pattern such as `[head, ...tail]`, the spread pattern matches the remaining
suffix of the input list.

::: info Example
```lx
[1, 2, 3]
[0, ...xs]
[1..5]
```
:::

## Operators

```wsn
disjunction = conjunction { "||" conjunction } .
conjunction = comparison { "&&" comparison } .
comparison = concat { ("==" | "!=" | "<" | ">" | "<=" | ">=") concat } .
concat = addition [ "++" concat ] .
addition = multiplication { ("+" | "-") multiplication } .
multiplication = unary { ("*" | "/" | "%") unary } .
unary = [ "-" | "!" ] application .
```

Operator precedence from high to low is:

<table>
    <thead>
        <tr>
            <th>Precedence</th>
            <th>Operators</th>
            <th>Associativity</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>8</td>
            <td><code>f(...)</code></td>
            <td>left to right</td>
        </tr>
        <tr>
            <td>7</td>
            <td><code>!</code>, <code>-</code> (unary)</td>
            <td>right to left</td>
        </tr>
        <tr>
            <td>6</td>
            <td><code>*</code>, <code>/</code>, <code>%</code></td>
            <td>left to right</td>
        </tr>
        <tr>
            <td>5</td>
            <td><code>+</code>, <code>-</code></td>
            <td>left to right</td>
        </tr>
        <tr>
            <td>4</td>
            <td><code>++</code></td>
            <td>right to left</td>
        </tr>
        <tr>
            <td>3</td>
            <td><code>==</code>, <code>!=</code>, <code>&lt;</code>, <code>&gt;</code>, <code>&lt;=</code>, <code>&gt;=</code></td>
            <td>left to right</td>
        </tr>
        <tr>
            <td>2</td>
            <td><code>&amp;&amp;</code></td>
            <td>left to right</td>
        </tr>
        <tr>
            <td>1</td>
            <td><code>||</code></td>
            <td>left to right</td>
        </tr>
    </tbody>
</table>

The operator `++` concatenates lists. Boolean conjunction `&&` and disjunction
`||` short-circuit from left to right.

::: info Example
```lx
let classify = (n) {
    ? n > 0 && n != 10 => "positive"
    ? n < 0 || n == -10 => "negative"
    => "zero"
};

classify(-3)
```
:::

## Dynamic Semantics

Evaluation is environment-based.

- Literals evaluate to themselves.
- Identifiers evaluate to the value currently bound to their name.
- A `let` binding evaluates its right-hand side, pattern-matches the result, and
  extends the environment for the following expression.
- A function literal evaluates to a closure containing its parameter list, body,
  and defining environment.
- Function application evaluates the callee, then the arguments from left to
  right, then applies the resulting function value.
- A block evaluates its inner expression sequence in a fresh local environment.

### Branch Selection

For a function body consisting of branches:

1. branches are examined from top to bottom
2. each branch pattern list is matched against the argument list
3. if matching succeeds, the guard is evaluated in the extended environment
4. the first successful branch body is evaluated and returned

If matching fails, the next branch is examined.

### Recursive Bindings

Only bindings that introduce a function value under a simple identifier pattern
are recursive. Bindings using other patterns, such as `let [f] = ...` or
`let _ = ...`, are not recursive.

## Pattern Matching

Pattern matching is structural.

- A literal pattern matches an equal literal value.
- An identifier pattern matches any value and binds it.
- `_` matches any value.
- A list pattern matches only a list of compatible shape.
- A spread pattern matches the remaining suffix of a list.

Pattern matching failure is local to the current branch or binding.

## Built-in Functions

Implementations may provide built-in functions in the initial environment. The
current reference implementation provides at least:

- `print`
- `exit`

## Errors

Evaluation halts with a runtime error in cases including:

- unbound identifiers
- non-boolean guards
- applying a non-function value
- argument count mismatch
- pattern match failure in a binding
- failure to select a branch

## Comparison with C

### Branching

::: info C Comparison
```c
int main(void) {
    int number = 5;

    if (number > 0) {
        printf("positive\n");
    } else if (number < 0) {
        printf("negative\n");
    } else {
        printf("zero\n");
    }

    return 0;
}
```

```lx
let number = 5;
let describe = (n) {
    n ? n > 0 => print("positive")
    n ? n < 0 => print("negative")
    _ => print("zero")
};

describe(number)
```
:::

### Iteration by Recursion

::: info C Comparison
```c
void fizzbuzz(int n) {
    if (n % 15 == 0) {
        printf("FizzBuzz\n");
    } else if (n % 3 == 0) {
        printf("Fizz\n");
    } else if (n % 5 == 0) {
        printf("Buzz\n");
    } else {
        printf("%d\n", n);
    }
}

int main(void) {
    for (int i = 1; i <= 15; i++) {
        fizzbuzz(i);
    }
    return 0;
}
```

```lx
let fizzbuzz = (n) {
    ? n % 15 == 0 => print("FizzBuzz")
    ? n % 3 == 0 => print("Fizz")
    ? n % 5 == 0 => print("Buzz")
    => print(n)
};

let loop = (i, max) {
    i, max ? i > max => print("Done.")
    _, _ => {
        fizzbuzz(i);
        loop(i + 1, max)
    }
};

loop(1, 15)
```
:::

### List Processing

::: info C Comparison
```c
int sum(int* xs, int n) {
    int total = 0;
    for (int i = 0; i < n; i++) total += xs[i];
    return total;
}

int main(void) {
    int xs[] = {1, 2, 3, 4, 5};
    int result = sum(xs, 5);
    printf("%d\n", result);
    return 0;
}
```

```lx
let sum = (xs) {
    [] => 0
    [head, ...tail] => head + sum(tail)
};

sum([1, 2, 3, 4, 5])
```
:::
