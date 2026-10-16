#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define env-eval (make-base-eval))
@interaction-eval[#:eval env-eval (require freer-lib racket/match)]

@title{Environment}

@defmodule[freer-lib/effects/env-effect]

This module provides an effect for reading a value from an environment, such as an environment variable or a configuration setting. What the environment is, and what keys it accepts, is decided entirely by the handler; there is no default handler.

The effect descriptor is defined as a record type with @racketmodname[rebellion/type/record], so it is constructed with a keyword argument.

@defproc[(read-env-effect [#:kw kw any/c]) read-env-effect?]{
  Constructs an effect descriptor that requests the value associated with the key @racket[kw].
}

@defproc[(read-env-effect? [v any/c]) boolean?]{
  Returns @racket[#t] if @racket[v] is a @racket[read-env-effect], @racket[#f] otherwise.
}

@defproc[(read-env-effect-kw [eff read-env-effect?]) any/c]{
  Returns the key requested by @racket[eff].
}

@defproc[(read-env [kw any/c]) free?]{
  Creates an effect that requests the value associated with the key @racket[kw].

  @examples[#:eval env-eval
    (define (greeting)
      (do-m [user <- (read-env "USER")]
            (return (format "Hello, ~a!" user))))

    (code:comment "A handler that reads from a fixed table instead of the real environment")
    (define (env-handler eff k)
      (match eff
        [(? read-env-effect?)
         (k (hash-ref (hash "USER" "alice") (read-env-effect-kw eff) #f))]))

    (run (greeting) env-handler)
  ]
}
