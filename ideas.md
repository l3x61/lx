# Ideas
## Getting rid of keywords
### let-in
```

let x = 1 in
let y = 2 in
  x + y

... as ...

x := 1
y := 2
  |- x + y

```

`N := E` "N is defined as E"

https://en.wikipedia.org/wiki/Turnstile_(symbol)

`Γ ⊢ φ` "from Γ, we can derive φ"

`Γ |- E` "under the environment Γ, the expression E is evaluated"


### if-then
ternary
```
if E then Et else Ef

E ? Et : Ef
```

### true/false

no symbols, logic operators convert to boolean implicitly ?
```
!!E
!E          logical not
E1 || E2    logical or
E1 && E2    logical and
E1 != E2    logical xor
```
