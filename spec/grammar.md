# Lx grammar
## Notation 
[Wirth syntax notation (WSN)](https://en.wikipedia.org/wiki/Wirth_syntax_notation)

- `|` alternation (either/or).
- `(` ... `)` grouping.
- `[` ... `]` optional (zero or one).
- `{` ... `}` repetition (zero or more).
- `"` ... `"` literal string.
- `""""` means a literal `"`.

```abnf
syntax     = { production } .
production = identifier "=" expression "." .
expression = term { "|" term } .
term       = factor { factor } .
factor     = identifier
           | literal
           | "[" expression "]" 
           | "(" expression ")"
           | "{" expression "}" .
identifier = LETTER { LETTER } .
literal    = """" CHARACTER { CHARACTER } """" .
```

## Grammar

### Local Conventions
- Non-terminals are lowercase.
- UPPERCASE names denote lexer tokens.
- The lexer ignores whitespace and line comments starting with `#` up to the end of the line.

```ebnf
program
    = [ expression ] 
    .
expression
    = let_rec_in
    | if_then_else
    | function
    | equality 
    .
let_rec_in
    = "let" ["rec"] IDENTIFIER "=" expression "in" expression 
    .
if_then_else
    = "if" expression "then" expression "else" expression 
    .
function
    = ("\\" | "λ") IDENTIFIER "." expression 
    .
equality
    = additive { ("==" | "!=") additive } 
    .
additive
    = multiplicative { ("+" | "-") multiplicative } 
    .
multiplicative
    = apply { ("*" | "/") apply } 
    .
apply
    = primary { primary } 
    .
primary
    = "null"
    | "true"
    | "false"
    | NUMBER
    | SYMBOL
    | function
    | "(" expression ")" 
    .
```

## Lexer Tokens
Note: literals like `if` or `λ` are also tokens but are not listed here.

#### NUMBER
```regex
[0-9]+
```

#### SYMBOL
Anything that isn't a keyword, literal, operator, or punctuation is tokenized as a SYMBOL.
```regex
[^\s()#\+\-\*/\.=\\λ][^\s()#\+\-\*/\.=\\λ]*
```

#### WHITESPACE (not shown in the grammar)
```regex
[\t\n\r \f\u0085\u00A0]+
```

#### COMMENT (not shown in the grammar)
```regex
#[^\n]*
```
