---
paths:
    - "**/*.rkt"
---

# Rules for writing procedures
- Write effectful code as monadic procedures. Each one returns a Freer monad value that describes its effects.
- Handle the effects in effect handlers. Do not perform them inside the procedure.
- Use the `freer-lib` skill for all monadic code.
