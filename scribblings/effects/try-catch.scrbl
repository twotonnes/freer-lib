#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define try-catch-eval (make-base-eval))
@interaction-eval[#:eval try-catch-eval (require freer-lib freer-lib/try-catch racket/match)]

@title{Try-Catch Pattern}

@defmodule[freer-lib/try-catch]

The try-catch pattern provides a mechanism for handling short-circuit failures in effectful computations. When a computation returns @racket[#f], the @racket[try] form captures this failure and allows an alternative computation to be executed instead.

@defproc[(try [computation free?] [fallback free?]) free?]{
  Executes a computation and evaluates a fallback computation if the original returns @racket[#f].

  When @racket[computation] returns @racket[#f], a @racket[failure-effect] is performed with the @racket[fallback] computation. If the computation returns any other value, that value is returned directly.

  This is typically used with @racket[catch] to handle the @racket[failure-effect]:

  @examples[#:eval try-catch-eval
    (define computation
      (do [x <- (return 10)]
          (if (> x 20)
              (return x)
              (return #f))))

    (run (catch
            (try computation (return 'fallback-value)))
        (lambda (eff k) (k 'default)))
  ]
}

@defproc[(catch [computation free?]) free?]{
  Interprets a computation that may produce @racket[failure-effect]s, converting them into successful computations.

  The @racket[catch] procedure installs an interpreter that handles @racket[failure-effect]s by returning their fallback computation. Any other effects are re-performed in the interpretation context.

  This allows computations using @racket[try] to properly handle failures:

  @examples[#:eval try-catch-eval
    (define failing-computation
      (do [a <- (return 1)]
          [b <- (try (return #f) (return 100))]
          (return (+ a b))))

    (run (catch failing-computation)
         (lambda (eff k) (k 'handler)))
  ]
}

@section{Usage Pattern}

The typical pattern for using try-catch is:

@itemlist[
  @item{Wrapping computations that might return @racket[#f] with @racket[try], providing a fallback}
  @item{Wrapping the entire computation sequence with @racket[catch] to install the failure interpreter}
  @item{If a computation returns @racket[#f], the fallback is used and subsequent computations are skipped}
  @item{If all computations succeed (return non-@racket[#f] values), the computation proceeds normally}
]

@examples[#:eval try-catch-eval
  (define (check-positive n)
    (if (positive? n)
        (return n)
        (return #f)))

  (define computation
    (do [a <- (check-positive 5)]
        [b <- (try (check-positive -3) (return 0))]
        [c <- (check-positive 10)]
        (return (+ a b c))))

  (run (catch computation)
       (lambda (eff k) (k 'error)))
]

