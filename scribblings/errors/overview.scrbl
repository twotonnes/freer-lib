#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define err-eval (make-base-eval))
@interaction-eval[#:eval err-eval (require racket freer-lib)]

@title{Error Handling}

This chapter describes the error-handling mechanisms that the library provides, when to use each, and how to build your own.

The library has no @tt{Maybe} or @tt{Either} values. Errors are either effects (resolved by a handler), a @racket[#f] result (resolved by @racket[catch]), or ordinary Racket exceptions raised by impure code.

@section{Available Mechanisms}

@subsection{The failure effect}

@defmodule[freer-lib/effects/failure-effect]

@defstruct[failure-effect ([msg any/c])]{
  An effect descriptor that carries a failure message.
}

@defproc[(failure [msg string?]) free?]{
  Describes a failure with the message @racket[msg] by performing a @racket[failure-effect].

  There is no default handler. The handler that you pass to @racket[run] decides what a failure means: raise an error, stop with a value, or recover.
}

@examples[#:eval err-eval
  (define (safe-div a b)
    (if (zero? b)
        (failure "division by zero")
        (return (/ a b))))

  (run (safe-div 6 3)
       (lambda (eff k)
         (match eff
           [(failure-effect msg) (return (list 'failed msg))])))

  (run (safe-div 1 0)
       (lambda (eff k)
         (match eff
           [(failure-effect msg) (return (list 'failed msg))])))
]

Because the handler does not call @racket[k], the rest of the computation is skipped.

@subsection{The abort effect}

Module @racketmodname[freer-lib/effects/abort-effect] (documented under Standard Effects). @racket[(abort)] describes an immediate stop, with no message, by performing an @racket[abort-effect]. A handler that does not call @racket[k] ends the computation.

@examples[#:eval err-eval
  (require freer-lib/effects/abort-effect)

  (define (check-positive x)
    (do-m [_ <- (if (negative? x) (abort) (return (void)))]
          (return x)))

  (run (check-positive -1)
       (lambda (eff k)
         (match eff
           [(abort-effect) (return 'stopped)])))
]

@subsection{try and catch}

Module @racketmodname[freer-lib/try-catch] (documented under Standard Effects). @racket[try] treats a @racket[#f] result as a failure. When the computation returns @racket[#f], @racket[try] signals an internal failure that carries the fallback computation. @racket[catch] intercepts that failure, discards the rest of the enclosed computation, and runs the fallback instead.

@examples[#:eval err-eval
  (run (catch
         (do-m [a <- (return 1)]
               [b <- (try (return #f) (return 'fallback))]
               (return (list a b))))
       (lambda (eff k) (k eff)))
]

@racket[catch] only intercepts failures raised by @racket[try]. It does @bold{not} intercept the @racket[failure] effect, which must be handled by the handler given to @racket[run].

@subsection{Exceptions}

The impure handlers (file system, commands, HTTP, logging) catch @racket[exn:fail?] exceptions from the outside world and re-raise them with @racket[error]. They reach the caller of @racket[run] as @racket[exn:fail]. To recover, wrap the call to @racket[run] in @racket[with-handlers].

Pure code must not raise: a failure that can occur with valid input is a value or an effect.

@section{Choosing a Mechanism}

@tabular[#:style 'boxed
         #:sep @hspace[2]
         (list (list @bold{Situation} @bold{Use})
               (list "A reportable error that a caller may handle" @racket[failure])
               (list "An early exit with no payload" @racket[abort])
               (list @elem{A single computation that returns @racket[#f] on failure} @elem{@racket[try] and @racket[catch]})
               (list "A failure of the outside world inside an impure handler" "an exception"))]

@itemlist[
  @item{Prefer @racket[failure] when the cause matters, since it carries a message and each @racket[run] can handle it differently, for example in tests.}
  @item{Prefer @racket[abort] when the only information is that the computation stopped.}
  @item{Use @racket[try] and @racket[catch] when you need a local fallback and the failure is naturally @racket[#f]. A legitimate @racket[#f] result is indistinguishable from a failure.}
  @item{Raise exceptions only in impure code, such as a handler.}
]

@section{Creating a Custom Mechanism}

Create your own when the existing ones cannot carry the information you need, for example a structured error with a code, or a recovery policy that is specific to your domain.

There is no macro for defining effects. A mechanism has three parts:

@itemlist[
  @item{a struct that describes the failure,}
  @item{a constructor that calls @racket[perform] on an instance of the struct,}
  @item{an interpreter, used as (or inside) the handler for @racket[run], that matches the struct and returns a value without calling @racket[k].}
]

@examples[#:eval err-eval
  (struct reject-effect (code))

  (define (reject code)
    (perform (reject-effect code)))

  (define (validate-age age)
    (cond [(not (integer? age)) (reject 'not-a-number)]
          [(negative? age) (reject 'negative)]
          [else (return age)]))

  (define (handle-reject eff k)
    (match eff
      [(reject-effect code) (return (list 'rejected code))]))

  (run (validate-age 30) handle-reject)
  (run (validate-age -5) handle-reject)
]

To recover inside a larger computation instead of ending the whole @racket[run], write an interpreter that walks the computation, as @racket[catch] does. It matches the computation: a @racket[pure] value is returned, your effect yields the fallback, and any other effect is forwarded by performing it again and continuing with the interpreter on the rest.

@examples[#:eval err-eval
  (define (recover-reject computation fallback)
    (match computation
      [(pure v) (return v)]
      [(impure (reject-effect _) _ _) (return fallback)]
      [(impure eff k _)
       (>>= (perform eff) (lambda (v) (recover-reject (k v) fallback)))]))

  (run (recover-reject
         (do-m [x <- (return 1)]
               [y <- (reject 'boom)]
               (return (+ x y)))
         'recovered)
       (lambda (eff k) (k eff)))
]
