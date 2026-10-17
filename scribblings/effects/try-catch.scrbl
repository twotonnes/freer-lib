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

  When @racket[computation] returns @racket[#f], an internal failure effect carrying the @racket[fallback] computation is performed. This effect is private to the @racket[freer-lib/try-catch] module and is distinct from the exported @racket[failure-effect]. If the computation returns any other value, that value is returned directly.

  This is typically used with @racket[catch] to handle the @racket[failure-effect]:

  @examples[#:eval try-catch-eval
    (define computation
      (do-m [x <- (return 10)]
          (if (> x 20)
              (return x)
              (return #f))))

    (run (catch
            (try computation (return 'fallback-value)))
        (lambda (eff k) (k 'default)))
  ]
}

@defproc[(catch [computation free?]) free?]{
  Interprets a computation that may fail through @racket[try]. At the first failure, the rest of the computation is discarded and the fallback computation is returned as the result; it is not run by @racket[catch] itself, so the result may still be a computation with effects.

  The @racket[catch] procedure walks the computation: a failure from @racket[try] yields its fallback computation, and any other effects are re-performed so an outer handler can interpret them.

  This allows computations using @racket[try] to properly handle failures:

  @examples[#:eval try-catch-eval
    (define failing-computation
      (do-m [a <- (return 1)]
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
    (do-m [a <- (check-positive 5)]
        [b <- (try (check-positive -3) (return 0))]
        [c <- (check-positive 10)]
        (return (+ a b c))))

  (run (catch computation)
       (lambda (eff k) (k 'error)))
]

