#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define std-eval (make-base-eval))
@interaction-eval[#:eval std-eval (require racket/match freer-lib)]

@title{Failure Effect}

@defmodule[freer-lib/effects/failure-effect]

The failure effect allows computations to signal failure with an error message. This is useful for error handling and control flow in effectful computations.

@defstruct*[failure-effect ([msg string?])]{
  A descriptor that represents a failure with an associated error message. The struct is opaque, so handlers should use @racket[failure-effect?] and @racket[failure-effect-msg] (or a @racket[struct] pattern in @racket[match]) to inspect it.
}

@defproc[(failure [msg string?]) free?]{
  Constructs an effect that signals failure with the given error message.

  There is no default handler. A handler typically does not resume the continuation, so that the rest of the computation is skipped.
}

The failure effect can be used to propagate errors through a computation, for example when the result of a command execution or HTTP request is not what was expected.

@examples[#:eval std-eval
  (define (check-size x)
    (do-m [v <- (id x)]
          (if (< v 20)
              (failure "Value is too small")
              (return v))))

  (define (handler eff k)
    (match eff
      [(id-effect v) (k v)]
      [(failure-effect msg) (return (format "failed: ~a" msg))]))

  (run (check-size 10) handler)
  (run (check-size 30) handler)
]
