#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [log-info r:log-info] [log-debug r:log-debug] [log-error r:log-error])
             freer-lib))

@(define std-eval (make-base-eval))
@interaction-eval[#:eval std-eval (require racket freer-lib)]

@title{Standard Effects}

While the core library allows you to define any effect you wish, this module provides a set of common, pre-defined effects for everyday tasks like Input/Output, HTTP requests, system commands, and logging.

These effects come with companion **default handlers**. You are not required to use these handlers—you can write your own interpreters for @racket[cmd-effect], @racket[http-effect], or @racket[log-effect] if you wish to mock them for testing—but the default handlers provide production-ready implementations.

@section{Understanding Basic Effects}

To understand how these standard effects work, consider the simplest one: the Identity effect.

@defmodule[freer-lib/effects/id-effect]

@defstruct[id-effect ([value any/c]) #:transparent]{
  A descriptor that simply holds a value.
}

@defproc[(id [v any/c]) impure?]{
  Constructs an effect that wraps @racket[v].
}

When you use @racket[id], you are effectively pausing the computation to hand a value to the handler, which is expected to hand it right back.

@examples[#:eval std-eval
  (define computation
    (do [x <- (id 10)]
        [y <- (id 20)]
        (return (+ x y))))

  ;; A handler that simply unwraps the ID and returns the value
  (run computation
       (lambda (eff k)
          (match eff
            [(id-effect v) (k v)])))
]

@include-section["cmd.scrbl"]
@include-section["http.scrbl"]
@include-section["abort-effect.scrbl"]
@include-section["log.scrbl"]
