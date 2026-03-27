#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [set r:set])
             freer-lib))

@(define common-eval (make-base-eval))
@interaction-eval[#:eval common-eval (require freer-lib)]

@section{Common Lenses}

@defmodule[freer-lib/lens/common-lenses]

This module provides ready-made lenses for common Racket data structures,
built on top of @racketmodname[freer-lib/lens/lens].

@defproc[(hash-lens [key any/c]) lens?]{
  Returns a lens that focuses on the value associated with @racket[key] in a
  hash table. The @emph{get} side uses @racket[hash-ref] and the @emph{set}
  side uses @racket[hash-set], producing a new hash rather than mutating the
  original.

  @examples[#:eval common-eval
    (define db (hash 'name "Alice" 'age 30))

    (view-l (hash-lens 'name) db)
    (set-l  (hash-lens 'age)  31 db)
    (over-l (hash-lens 'age)  add1 db)
  ]
}

@defform[(struct-lens id field-id)]{
  Constructs a lens that focuses on @racket[field-id] within an instance of the
  struct @racket[id]. The accessor @racket[id-field-id] is used for @emph{get},
  and @racket[struct-copy] is used for @emph{set} so the original instance is
  never mutated.

  @examples[#:eval common-eval
    (struct point (x y) #:transparent)

    (define point-x (struct-lens point x))
    (define point-y (struct-lens point y))

    (define p (point 3 7))

    (view-l point-x p)
    (set-l  point-y 42 p)
    (over-l point-x add1 p)
  ]
}
