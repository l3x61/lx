# Lx

## Syntax

```wsn
Program 
    = Expression .

Expression 
    = Binding
    | MatchExpr
    | LogicOr .

Binding 
    = "let" BindPattern "=" Expression ";" Expression .

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
    = BindPattern "->" Expression .

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
