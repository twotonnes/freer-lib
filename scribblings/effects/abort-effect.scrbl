#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [log-info r:log-info] [log-debug r:log-debug] [log-error r:log-error])
             freer-lib))

@(define abort-eval (make-base-eval))
@interaction-eval[#:eval abort-eval (require freer-lib freer-lib/effects/abort-effect racket/match)]

@title{Abort Effect}

@defmodule[freer-lib/effects/abort-effect]

The abort effect allows computations to signal immediate termination without producing a value.

@defstruct[abort-effect () #:transparent]{
  An effect descriptor that represents an abort signal. The struct has no fields.
}

@defproc[(abort) free?]{
  Creates an effect that signals termination of the current computation.

  @examples[#:eval abort-eval
    (define (conditional-abort x)
      (do [_ <- (if (negative? x)
                    (abort)
                    (return (void)))]
          (return (abs x))))
  ]
}

The abort effect is useful for control flow when you need to exit a computation early without producing a normal return value.
