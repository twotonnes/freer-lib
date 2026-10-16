#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define abort-eval (make-base-eval))
@interaction-eval[#:eval abort-eval (require freer-lib freer-lib/effects/abort-effect racket/match)]

@title{Abort Effect}

@defmodule[freer-lib/effects/abort-effect]

The abort effect allows computations to signal immediate termination without producing a value.

@defstruct*[abort-effect ()]{
  An effect descriptor that represents an abort signal. The struct has no fields and is opaque.
}

@defproc[(abort) free?]{
  Creates an effect that signals termination of the current computation.

  There is no default handler. A handler typically implements an abort by @emph{not} calling the continuation and returning some final computation instead, which discards the rest of the computation.

  @examples[#:eval abort-eval
    (define (conditional-abort x)
      (do-m (if (negative? x)
                (abort)
                (return (void)))
            (return (abs x))))

    (define (handler eff k)
      (match eff
        [(? abort-effect?) (return 'aborted)]))

    (run (conditional-abort 5) handler)
    (run (conditional-abort -5) handler)
  ]
}

The abort effect is useful for control flow when you need to exit a computation early without producing a normal return value.
