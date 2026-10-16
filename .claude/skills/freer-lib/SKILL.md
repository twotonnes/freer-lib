---
name: freer-lib
description: Use this skill whenever writing monadic code. This includes algebraic effects, Freer monads, pure code, effects, handlers, `perform`, `run`, `>>=`, `bind`, and `do`. Load it before proposing, creating, reviewing, or refactoring monadic or effectful code. Do not infer freer-lib syntax from unrelated online sources.
---

# freer-lib conventions
`freer-lib` is the project's library for representing algebraic effects with a Freer monad. It separates a program's description of effects from their execution.

Use this skill for code that uses the library. It covers the usage that most code needs.

# Referencing documentation
Read the library documentation at "https://twotonnes.github.io/freer-lib/" only when this skill does not answer the question.

# Guidance
1. Find a similar example in the project first. For example, when creating `api-handler/login.rkt`, open another handler in the same directory and copy its structure.
2. If no example exists, follow the patterns below.

## Writing monadic procedures
Most code will be in the form of monadic procedures. These center around a function called `do-m`, which has the following syntax:

```
(do-m clause ...)
 
clause = [id <- expr]
 	   | expr
```

do-m is a monadic sequencing macro similar to Haskell’s do-notation. It expands into nested calls to >>=.

- `[id <- expr]`: Runs expr, and binds its result to `id` for the remaining clauses. The binding uses `match`, so `id` must be a valid match pattern.
- `expr`: Runs expr for its side effects, discards the result, and continues.

The final expression sets the value of the whole `do-m` block.

Examples:
```racket
(struct ask (question))
(define (ask-user q) (impure (ask q) return))
(define survey-computation
    (do-m [name <- (ask-user "What is your name?")]
        [age  <- (ask-user "What is your age?")]
        (return (format "~a is ~a years old." name age))))
(run survey-computation
       (lambda (eff k)
         (match eff
           [(ask "What is your name?") (k "Alice")]
           [(ask "What is your age?") (k 30)])))
```
Returns: `"Alice is 30 years old."`

## Running monadic expressions
Instead of performing effectful code, monadic procedures return instances of the Freer monad that describe effectful programs. In order to run these programs, a procedure `run` can be used, which has the following syntax:

```
(run m handle) → any/c
  m : (or/c pure? impure?)
  handle : (-> any/c (-> any/c (or/c pure? impure?)) (or/c pure? impure?))
```

Run executes an effectful computation m by repeatedly resolving effects using the provided handle function.

When run encounters a pure value, it returns the unwrapped value. When it encounters an impure, it extracts the effect description and continuation, then passes them to handle as separate arguments. The handler can process the effect and resume the computation by calling the continuation k, or it can return a new computation to continue execution.

Examples:
```racket
(struct read-env (var-name))
(define my-computation
    (do-m [path <- (perform (read-env "HOME"))]
        (return (string-append "Home is: " path))))
(run my-computation
       (lambda (eff k)
         (match eff
           [(read-env var)
            (k "/usr/home/racket-user")])))
```
Returns: `"Home is: /usr/home/racket-user"`

## Defining and using effects
Effects are defined as structs, and helper procedures are used in combination with `perform` to create instances of the monad that describes the effect.

Example for a simple effect called `id-effect` (a pass-through, no-op effect) and helper procedure `id`:

```racket
(struct id-effect (value) #:transparent)

(define/contract (id v)
  (-> any/c free?)
  (perform (id-effect v)))
  
(define my-computation
    (do-m
        [one <- (id 1)]
        [two <- (id 2)]
        (return (+ one two))))
        
(run my-computation
       (lambda (eff k)
         (match eff
           [(id v)
            (k v)])))
```
Returns: `3`
