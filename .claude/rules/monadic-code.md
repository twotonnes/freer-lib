---
paths:
    - "**/*.rkt"
---

# Rules for writing procedures
- Write effectful code as monadic procedures. Each one returns a Freer monad value that describes its effects.
- Handle the effects in effect handlers. Do not perform them inside the procedure.
- Find similar monadic code in this project and copy its pattern before writing new code.
- Look up freer-lib usage at https://twotonnes.github.io/freer-lib/ only when the project code does not answer the question.
