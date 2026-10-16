#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [set r:set])
             freer-lib))

@(define lens-eval (make-base-eval))
@interaction-eval[#:eval lens-eval (require freer-lib racket/list)]

@section{Core Lens}

@defmodule[freer-lib/lens/lens]

This module provides the core lens abstraction — a composable pair of @emph{get}
and @emph{set} functions that enables focused, immutable access into nested
data structures.

@defstruct*[lens ([get (-> any/c any/c)] [set (-> any/c any/c any/c)]) #:transparent]{
  A first-class lens value pairing a getter and a setter.

  @itemlist[
    @item{@racket[get]: A procedure that takes a structure and extracts the
          focused value from it.}
    @item{@racket[set]: A procedure that takes a new value and a structure (in
          that order) and returns a new structure with the focused value
          replaced.}
  ]

  Lenses are expected to obey the usual lens laws: viewing after setting
  returns the value that was set, setting the value that was just viewed
  returns an equal structure, and setting twice is the same as setting once
  with the last value.

  @examples[#:eval lens-eval
    (define first-lens
      (lens first
            (lambda (new-v lst) (list-set lst 0 new-v))))
    first-lens
  ]
}

@defproc[(view-l [l lens?] [structure any/c]) any/c]{
  Extracts the focused value from @racket[structure] using the lens @racket[l].

  @examples[#:eval lens-eval
    (view-l first-lens '(10 20 30))
  ]
}

@defproc[(set-l [l lens?] [new-value any/c] [structure any/c]) any/c]{
  Returns a new structure with the focused position updated to @racket[new-value].

  @examples[#:eval lens-eval
    (set-l first-lens 99 '(10 20 30))
  ]
}

@defform[(set-l* structure [l new-v] ...)]{
  A syntactic shorthand for chaining multiple @racket[set-l] operations on a single
  @racket[structure]. Each @racket[[l new-v]] clause is applied left-to-right.
  Returns @racket[structure] unchanged when no clauses are provided.

  @examples[#:eval lens-eval
    (define second-lens
      (lens second
            (lambda (new-v lst) (list-set lst 1 new-v))))

    (set-l* '(1 2 3)
          [first-lens 10]
          [second-lens 20])
  ]
}

@defproc[(over-l [l lens?] [update-fn (-> any/c any/c)] [structure any/c]) any/c]{
  Applies @racket[update-fn] to the focused value inside @racket[structure] and
  returns the updated structure. Equivalent to
  @racket[(set-l l (update-fn (view-l l structure)) structure)].

  @examples[#:eval lens-eval
    (over-l first-lens add1 '(10 20 30))
  ]
}

@defform[(lens-compose l1 l2 ...)]{
  Composes one or more lenses from the outside in: @racket[l1] focuses on a part
  of the structure, the first @racket[l2] focuses on a part of what @racket[l1]
  focuses on, and so on. Setting through the composed lens rebuilds every
  intermediate structure. With a single lens, @racket[(lens-compose l1)] is
  @racket[l1].

  @examples[#:eval lens-eval
    (define nested '((1 2) (3 4)))

    (define first-of-second
      (lens-compose second-lens first-lens))

    (view-l first-of-second nested)
    (set-l  first-of-second 99 nested)
  ]
}
