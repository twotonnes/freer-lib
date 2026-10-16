#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define std-eval (make-base-eval))
@interaction-eval[#:eval std-eval (require racket freer-lib)]

@title{Standard Effects}

@defmodule[freer-lib/effects/main]

While the core library allows you to define any effect you wish, this module provides a set of common, pre-defined effects for everyday tasks like file I/O, HTTP requests, system commands, logging, and random numbers. The @racketmodname[freer-lib/effects/main] module re-exports every effect module described in this section, and is itself re-exported by @racketmodname[freer-lib].

Some of these effects come with companion @bold{default handlers}: plain procedures that actually perform the requested operation (for example @racket[execute-command], @racket[perform-http-request], @racket[write-log], @racket[do-rnd] and the @racket[do-read-file] family). No handler is installed automatically; you always write the handler passed to @racket[run] yourself, and decide per effect whether to call a default handler or to mock the effect, e.g. for testing.

@section{Understanding Basic Effects}

To understand how these standard effects work, consider the simplest one: the Identity effect.

@defmodule[freer-lib/effects/id-effect]

@defstruct*[id-effect ([value any/c]) #:transparent]{
  A descriptor that simply holds a value.
}

@defproc[(id [v any/c]) free?]{
  Constructs an effect that wraps @racket[v].
}

When you use @racket[id], you are effectively pausing the computation to hand a value to the handler, which is expected to hand it right back.

@examples[#:eval std-eval
  (define computation
    (do-m [x <- (id 10)]
        [y <- (id 20)]
        (return (+ x y))))

  (code:comment "A handler that simply unwraps the ID and returns the value")
  (run computation
       (lambda (eff k)
          (match eff
            [(id-effect v) (k v)])))
]

@include-section["cmd.scrbl"]
@include-section["http.scrbl"]
@include-section["abort-effect.scrbl"]
@include-section["failure.scrbl"]
@include-section["log.scrbl"]
@include-section["file-system-effect.scrbl"]
@include-section["env.scrbl"]
@include-section["rnd.scrbl"]
@include-section["try-catch.scrbl"]
