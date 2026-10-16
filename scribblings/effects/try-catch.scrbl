#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define try-catch-eval (make-base-eval))
@interaction-eval[#:eval try-catch-eval (require freer-lib freer-lib/try-catch racket/match)]

@title{Try-Catch Pattern}

@defmodule[freer-lib/try-catch]

The try-catch pattern provides a mechanism for short-circuiting effectful computations. A computation wrapped with @racket[try] that returns @racket[#f] aborts the computation up to the nearest enclosing @racket[catch], and the fallback given to @racket[try] is used as the result of that @racket[catch] instead.

@defproc[(try [computation free?] [fallback free?]) free?]{
  Runs @racket[computation]. If its result is anything other than @racket[#f], that result is returned unchanged. If its result is @racket[#f], an internal failure effect carrying @racket[fallback] is performed, which the nearest enclosing @racket[catch] handles by discarding the rest of its computation and continuing with @racket[fallback].

  The failure effect is private to this module, so @racket[try] must be used inside a @racket[catch]; otherwise the failure effect reaches the handler given to @racket[run], which cannot recognize it.

  @examples[#:eval try-catch-eval
    (define computation
      (do-m [x <- (return 10)]
            (if (> x 20)
                (return x)
                (return #f))))

    (run (catch (try computation (return 'fallback-value)))
         (lambda (eff k) (k eff)))
  ]
}

@defproc[(catch [computation free?]) free?]{
  Handles the failures raised by @racket[try] inside @racket[computation]. When a failure occurs, the remainder of @racket[computation] is skipped and the resulting computation continues with the fallback that was passed to @racket[try]. All other effects are passed on unchanged, so they are handled by the enclosing handler (or an enclosing @racket[catch]), and @racket[computation] resumes with their result as usual.

  @examples[#:eval try-catch-eval
    (define (handler eff k)
      (match eff
        ['get-number (k 2)]))

    (define failing-computation
      (do-m [a <- (perform 'get-number)]
            [b <- (try (return #f) (return 100))]
            (return (+ a b))))

    (code:comment "The fallback replaces the whole caught computation")
    (run (catch failing-computation) handler)

    (code:comment "Code outside the catch continues with the fallback's result")
    (run (do-m [a <- (perform 'get-number)]
               [b <- (catch (try (return #f) (return 100)))]
               (return (+ a b)))
         handler)
  ]
}

@section{Usage Pattern}

The typical pattern for using try-catch is:

@itemlist[
  @item{Wrap computations that might return @racket[#f] with @racket[try], providing a fallback.}
  @item{Wrap the sequence of computations that should be aborted on failure with @racket[catch].}
  @item{If a computation wrapped in @racket[try] returns @racket[#f], the computations after it (up to the @racket[catch]) are skipped, and the @racket[catch] produces the result of the fallback.}
  @item{If all computations succeed (return non-@racket[#f] values), the computation proceeds normally.}
]

@examples[#:eval try-catch-eval
  (define (check-positive n)
    (if (positive? n)
        (return n)
        (return #f)))

  (define (sum-of-positives x y z)
    (do-m [a <- (try (check-positive x) (return 'not-positive))]
          [b <- (try (check-positive y) (return 'not-positive))]
          [c <- (try (check-positive z) (return 'not-positive))]
          (return (+ a b c))))

  (run (catch (sum-of-positives 5 3 10))
       (lambda (eff k) (k eff)))
  (run (catch (sum-of-positives 5 -3 10))
       (lambda (eff k) (k eff)))
]
