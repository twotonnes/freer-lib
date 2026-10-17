#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define std-eval (make-base-eval))
@interaction-eval[#:eval std-eval (require racket freer-lib)]

@title[#:tag "Failure Effect"]{Failure Effect}

@defmodule[freer-lib/effects/failure-effect]

The failure effect allows computations to signal failure with an error message. This is useful for error handling and control flow in effectful computations.

@defstruct[failure-effect ([msg string?])]{
  A descriptor that represents a failure with an associated error message.
}

@defproc[(failure [msg string?]) free?]{
  Constructs an effect that signals failure with the given error message.
}

The failure effect is often used in conjunction with error handling in other effects. When an error occurs during command execution or HTTP requests, the @racket[failure] effect can be used to propagate the error through the computation.

@examples[#:eval std-eval
  (define computation
    (do-m [x <- (id 10)]
        (if (< x 20)
            (failure "Value is too small")
            (return x))))
]
