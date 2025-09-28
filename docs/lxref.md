# Lx Reference

## Grammar
```wsn
program = [ expression ] EOF .

expression = binding | selection | equality .

binding = "let" IDENTIFIER "=" expression "in" expression .

selection = "if" expression "then" expression "else" expression .

equality = additive { ("==" | "!=") additive } .
additive = multiplicative { ("+" | "-") multiplicative } .
multiplicative = application { ("*" | "/") application } .

application = primary { primary } .

primary
    = literal
    | IDENTIFIER
    | function
    | "(" expression ")"
    .

literal
    = "true"
    | "false"
    | NUMBER
    | STRING

function = ("\\" | "λ") IDENTIFIER "." expression .
```


### Program
```wsn
program = [ expression ] EOF .
```

A program is either empty or a single expression.


### Expressions
```wsn
expression = binding | selection | equality .
```


#### Bindings
```wsn
binding = "let" IDENTIFIER "=" expression "in" expression .
```

A binding introduces a new variable, which is then available in the body.

::: info Example: Binding
```lx
let var = 123 in
    var
# evaluates to
    123
```
:::

Since bindings are expressions it is possible to chain them:


::: info Example: Chained Bindings
```lx
let a = 123 in
let b = 456 in
let add = \a. \b. a + b in
    add a b
# evaluates to
    579
```
:::


#### Selections
```wsn
selection = "if" expression "then" expression "else" expression .
```

A selection expression chooses between two alternatives based on a condition.

::: info Example: Selection
```lx
if a == b then
    "equal"
else
    "not equal"
```
:::

::: info Example: Chained Selection
```lx
if a == b then
    "equal"
else if a > b then
    "greater"
else
    "less"
```
:::


#### Infix
```wsn
equality = additive { ("==" | "!=") additive } .
additive = multiplicative { ("+" | "-") multiplicative } .
multiplicative = application { ("*" | "/") application } .
```

::: info Example: Infix Expressions
```lx
1 + 2 * 3 == 7
# parsed as
    (1 + (2 * 3)) == 7
```
:::


#### Application
```wsn
application = primary { primary } .
```
An application expression applies a function to one or more arguments.

::: info Example: Function Application
```lx
(λx. λy. x + y) 1 2  ==  ((λx. λy. x + y) 1) 2
```
:::


#### Primary
```wsn
primary
    = literal
    | IDENTIFIER
    | function
    | "(" expression ")"
    .
```


##### Literals
```wsn
literal
    = "true"
    | "false"
    | NUMBER
    | STRING
```

- **Boolean literals**: `true`, `false`
- **Numeric literals**: integers (e.g. `123`, `456`, …)
- **String literals**: sequences of characters enclosed in quotes

::: info Example: Literals
```lx
true
123
"hello"
```
:::


##### Identifiers

Identifiers refer to variables bound in the current scope.

::: info Example: Identifier
```lx
let foo = 42 in
    foo
# evaluates to
    42
```
:::


##### Grouping

Parentheses can group subexpressions and override precedence.

::: info Example: Parenthesized Expression
```lx
(1 + 2) * 3
# evaluates to
    9
```
:::


##### Abstraction
```wsn
function = ("\\" | "λ") IDENTIFIER "." expression .
```

A function abstraction introduces a parameter and a body.
The parameter binds occurrences of the identifier within the body.

::: info Example: Identity Function
```lx
let id = λx. x in
    id 1
# evaluates to
    1
```

```lx
let id = λx. x in
    id id
# evaluates to
    λx. x
```
:::

::: info Example: Curried Function
```lx
let add = λx. λy. x + y in
    add 1 2
# evaluates to
    3
```
```lx
let add = λx. λy. x + y in
    add 1
# evaluates to ...
    λy. 1 + y
# ... an expression where x is bound to the argument
```
```lx
let add = λx. λy. x + y in
    add (add 1 2) 3
# evaluates to
    6
```
:::
