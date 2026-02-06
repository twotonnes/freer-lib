#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [log-info r:log-info] [log-debug r:log-debug] [log-error r:log-error])
             freer-lib))

@(define std-eval (make-base-eval))
@interaction-eval[#:eval std-eval (require racket freer-lib)]

@title{Fail Effect}

@defmodule[freer-lib/effects/fail-effect]

The fail effect allows computations to signal failure with an error message. This is useful for error handling and control flow in effectful computations.

@defstruct[fail-effect ([msg string?]) #:transparent]{
  A descriptor that represents a failure with an associated error message.
}

@defproc[(fail [msg string?]) free?]{
  Constructs an effect that signals failure with the given error message.
}

The fail effect is often used in conjunction with error handling in other effects. When an error occurs during command execution or HTTP requests, the @racket[fail] effect can be used to propagate the error through the computation.

@examples[#:eval std-eval
  (define computation
    (do [x <- (id 10)]
        (if (< x 20)
            (fail "Value is too small")
            (return x))))
]
