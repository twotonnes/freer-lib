#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             json
             freer-lib))

@(define json-eval (make-base-eval))
@interaction-eval[#:eval json-eval (require freer-lib racket/match)]

@title{JSON}

@defmodule[freer-lib/json/main]

This module provides helpers for working with JSON inside effectful computations.

@defproc[(string->free-jsexpr [str string?]
                              [log-level (or/c 'dbg 'inf 'err)])
         free?]{
  Parses @racket[str] as JSON with @racket[string->jsexpr] and returns the resulting @racket[jsexpr?] as a computation.

  If @racket[str] cannot be parsed, no exception is raised. Instead, the computation logs a message describing the error and the offending string, using @racket[log-dbg], @racket[log-inf] or @racket[log-err] depending on @racket[log-level], and then performs @racket[abort]. The handler therefore needs to handle both @racket[log-effect] and @racket[abort-effect].

  @examples[#:eval json-eval
    (define (handler eff k)
      (match eff
        [(log-effect level msg) (k (void))]
        [(? abort-effect?) (return 'aborted)]))

    (run (string->free-jsexpr "{\"name\": \"Alice\", \"age\": 30}" 'err) handler)
    (run (string->free-jsexpr "{not json" 'err) handler)
  ]
}
