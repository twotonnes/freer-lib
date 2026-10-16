#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define rnd-eval (make-base-eval))
@interaction-eval[#:eval rnd-eval (require freer-lib racket/match)]

@title{Random Numbers}

@defmodule[freer-lib/effects/rnd-effect]

This module provides an effect for generating random integers. Keeping randomness behind an effect makes computations that use it deterministic under test.

@defstruct*[rnd-effect ([min exact-integer?]
                        [max exact-integer?]) #:transparent]{
  An effect descriptor that requests a random integer in the range from @racket[min] (inclusive) to @racket[max] (exclusive).
}

@defproc[(rnd [min exact-integer?] [max exact-integer?]) free?]{
  Creates an effect that requests a random integer @racket[n] such that @racket[(<= min n)] and @racket[(< n max)].

  @examples[#:eval rnd-eval
    (define roll-two-dice
      (do-m [a <- (rnd 1 7)]
            [b <- (rnd 1 7)]
            (return (+ a b))))

    (code:comment "A deterministic handler for testing that always returns the minimum")
    (run roll-two-dice
         (lambda (eff k)
           (match eff
             [(rnd-effect min max) (k min)])))
  ]
}

@defproc[(do-rnd [min exact-integer?] [max exact-integer?]) exact-integer?]{
  The default handler for @racket[rnd-effect]. Returns @racket[(random min max)], so @racket[min] must be less than @racket[max] and the range is subject to the limits of @racket[random].

  @racketblock[
    (run roll-two-dice
         (lambda (eff k)
           (match eff
             [(rnd-effect min max) (k (do-rnd min max))])))
  ]
}
