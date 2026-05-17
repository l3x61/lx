# Lx

**Lx**, also written **λx** or **Lambda expression**, is a dynamically-typed
functional language investigating pattern-based function abstractions as its
primary control-flow model.

## Requirements

- [Zig](https://ziglang.org/) `0.16.0`
- (Recommended) [just](https://github.com/casey/just) `1.40.0` lower may work (not tested)
- (Optional) [bat](https://github.com/sharkdp/bat) `0.26.1` lower may work (not tested)
- (Optional) [docker](https://www.docker.com/) `29.3.1` lower may work (not tested)

## Usage

All workflows are wired up in the [`justfile`](justfile). Run `just`
(or `just --list`) to see the recipes; without `just`, copy the command
line out of the `justfile` and run it directly.


## Syntax (Wirth EBNF)

```wsn
Program 
    = Expression .

Expression 
    = Bind { ";" Bind } .

Bind 
    = Binding
    | NonBind .

NonBind 
    = MatchExpr
    | LogicOr .

Binding 
    = "let" BindPattern "=" NonBind ";" Expression .

MatchExpr 
    = "match" LogicOr Function .

LogicOr 
    = LogicAnd { "||" LogicAnd } .

LogicAnd 
    = Equality { "&&" Equality } .

Equality 
    = Comparison [ ( "==" | "!=" ) Comparison ] .

Comparison 
    = Concat [ ( "<" | "<=" | ">" | ">=" ) Concat ] .

Concat 
    = Cons { "++" Cons } .

Cons 
    = Additive [ "::" Cons ] .

Additive 
    = Multiplicative { ( "+" | "-" ) Multiplicative } .

Multiplicative 
    = Prefix { ( "*" | "/" | "%" ) Prefix } .

Prefix 
    = ( "-" | "!" ) Prefix
    | Postfix .

Postfix 
    = Primary { CallSuffix | IndexSuffix | MemberSuffix } .

CallSuffix 
    = "(" [ Expression { "," Expression } ] ")" .

IndexSuffix
    = "[" Expression "]" .

MemberSuffix 
    = "." IDENTIFIER .

Primary 
    = IDENTIFIER
    | INTEGER
    | STRING
    | "true"
    | "false"
    | ParenExpr
    | ListExpr
    | RecordExpr
    | Function .

ParenExpr 
    = "(" ")"
    | "(" Expression { "," Expression } ")" .

ListExpr 
    = "[" [ Expression { "," Expression } ] "]" .

RecordExpr 
    = "{" [ RecordEntry { "," RecordEntry } ] "}" .

RecordEntry 
    = RecordKey ":" Expression .

RecordKey 
    = IDENTIFIER | STRING .

Function 
    = ( "\" | "λ" ) Clause { "|" Clause } .

Clause 
    = BindPattern "->" NonBind .

BindPattern 
    = Pattern { "," Pattern } .

Pattern 
    = AltPattern .

AltPattern 
    = RefinePattern { "|" RefinePattern } .

RefinePattern 
    = AtomicPattern { "&" Expression } .

AtomicPattern 
    = "_"
    | IDENTIFIER
    | INTEGER | STRING | "true" | "false"
    | "-" INTEGER
    | PatternParen
    | PatternList
    | PatternRecord .

PatternParen 
    = "(" ")"
    | "(" Pattern { "," Pattern } ")" .

PatternList 
    = "[" "]"
    | "[" ".." [ Pattern ] "]"
    | "[" Pattern { "," Pattern } [ "," ".." [ Pattern ] ] "]" .

PatternRecord 
    = "{" "}"
    | "{" ".." [ Pattern ] "}"
    | "{" RecordPatternEntry { "," RecordPatternEntry } [ "," ".." [ Pattern ] ] "}" .

RecordPatternEntry 
    = RecordKey ":" Pattern .


IDENTIFIER = ( LETTER | "_" ) { LETTER | DIGIT | "_" } .

INTEGER = DIGIT { DIGIT } .

STRING = DOUBLE_STRING | SINGLE_STRING .

DOUBLE_STRING = """" { STRING_CHARACTER | ESCAPE } """" .

SINGLE_STRING = "'" { STRING_CHARACTER | ESCAPE } "'" .

ESCAPE = "\" ( "\" | """" | "'" | "n" | "r" | "t" ) .

STRING_CHARACTER = . # any character except newline, unescaped quote or backslash

LETTER = . # [a-zA-Z]

DIGIT = . # [0-9]
```
