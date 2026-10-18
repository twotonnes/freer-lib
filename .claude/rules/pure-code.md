---
paths:
    - "**/*.rkt"
---

# Pure and impure code
- Classify every procedure as pure or impure. Pure code returns values, or monads that describe effects, and never performs them. A procedure that returns a monad is pure.
- Effect handlers are the only code that performs effects, for example mutating a store. Impure code is the handlers and what they call. See [[file:../../design/decisions/0003-pure-and-effectful-code.org][decision 0003]].
- Mark each impure procedure in its name: a `!` suffix, or a name that states the effect.
- Pure and impure code may share a source file.

## Pure code must not
- Raise exceptions for incorrect program state. Exceptions are only for incorrect syntax or misuse of the API, such as a missing argument, a wrong macro form, or a wrong number of arguments. Do not let exceptions from called procedures such as `car`, `vector-ref`, or `integer->char` on invalid input escape.
- Use randomness, the clock, I/O, or other outside state: `random`, `current-seconds`, `printf`.
- Mutate state: `set!`, `hash-set!`, `vector-set!`, mutable hashes.
- Use runtime contracts (`define/contract`, `->`, `->i`, `provide/contract`). See [[file:../../design/decisions/0001-no-contracts.org][decision 0001]].

## Use these instead
- Describe outside interactions as effects with freer-lib: `rnd` instead of `random`, `log-inf` instead of `printf`.
- Describe failures, which indicate incorrect program state such as reading a key that does not exist, as values or effects, such as a `failure` effect, instead of exceptions.
- Wrap calls that can raise, such as `/` on zero, in `with-handlers`, and return the result as a value.
- Pass state through arguments and return values, for example an immutable hash. A handler for a read-only effect, such as an environment, may read a value that the caller supplies. A handler for a read-write effect, such as a store, owns the storage it uses. The owner of a handler owns its state; the caller that calls the handler owns the store.
- Write each procedure's type as a comment directly above its definition, for example `;; Type: (-> Integer Integer)`. The code-writer does this for every procedure.
- Write tests that pass arguments of the types the comment allows, and cover every branch. Tests are the only check on types.

## Failure values
- Return a failure value or a monad for a failure that can happen with valid input, such as a lookup that finds nothing. Use freer-lib's `failure` effect or `try`/`catch`, so callers handle it.
- Do not make a procedure monadic only to avoid an exception. If a plain failure value works and its callers already handle it, return the value, as `evaluate-program` returns an `evaluation-failure`.
- Describe every outside interaction as an effect.

## Impure code
- Keep impure code as small as possible. Only code that touches the outside world is impure: for example an HTTP handler, a file-system handler, or a clock or randomness handler.
- Handlers perform the effects. Keep them small, and keep logic in pure procedures.
- The top-level handler may raise on an unknown effect or an unhandled `failure`.
- Impure helpers may raise on outside-world errors, such as an unreadable file. The user's handler decides whether to catch them, convert them to a failure, or abort. See [[file:../../design/decisions/0003-pure-and-effectful-code.org][decision 0003]].

## Monadic code
A procedure that returns a monad is pure, even if the monad describes an effect. Only the handler, which performs the effect, is impure.

## Tests
These rules apply to production code only. Tests in `(module+ test ...)` may raise exceptions, and test handlers may fail on unexpected effects.
