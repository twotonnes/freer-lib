---
paths:
    - "**/*.rkt"
---

# Pure and impure code
- Classify every procedure as pure or impure. Pure code's result depends only on its arguments and has no side effects. Impure code touches the outside world.
- Mark each impure procedure in its name: a `!` suffix, or a name that states the effect.
- Pure and impure code may share a source file.

## Pure code must not
- Raise exceptions: `error`, `raise`, failing `match`, or `car`, `vector-ref`, `integer->char` on invalid input. Also do not let exceptions from called procedures escape.
- Use randomness, the clock, I/O, or other outside state: `random`, `current-seconds`, `printf`.
- Mutate state: `set!`, `hash-set!`, `vector-set!`, mutable hashes.
- Use runtime contracts (`define/contract`, `->`, `->i`, `provide/contract`). See [[file:../../design/decisions/0001-no-contracts.org][decision 0001]].

## Use these instead
- Describe outside interactions as effects with freer-lib: `rnd` instead of `random`, `log-inf` instead of `printf`.
- Describe failures as values or effects, such as a `failure` effect, instead of exceptions.
- Wrap calls that can raise, such as `/` on zero, in `with-handlers`, and return the result as a value.
- Pass state through arguments and return values, for example an immutable hash. For state-only effects such as an environment, write a pure handler that takes a computation and returns a computation, threading the state through its recursion.
- Write each procedure's type as a comment directly above its definition, for example `;; Type: (-> Integer Integer)`. The code-writer does this for every procedure.
- Write tests that pass arguments of the types the comment allows, and cover every branch. Tests are the only check on types.

## Failure values
- Return a failure value or a monad for a failure that can happen with valid input, such as a lookup that finds nothing. Use freer-lib's `failure` effect or `try`/`catch`, so callers handle it.
- Do not make a procedure monadic only to avoid an exception. If a plain failure value works and its callers already handle it, return the value, as `evaluate-program` returns an `evaluation-failure`.
- Describe every outside interaction as an effect.

## Impure code
- Keep impure code as small as possible. Only code that touches the outside world is impure: for example an HTTP handler, a file-system handler, or a clock or randomness handler.
- Only impure procedures may raise. The top-level handler may raise on an unknown effect or an unhandled `failure`.

## Monadic code
A procedure that returns a monad is pure, even if the monad describes an effect. Only the code that performs the effect, the handler, is impure.

## Tests
These rules apply to production code only. Tests in `(module+ test ...)` may raise exceptions, and test handlers may fail on unexpected effects.
