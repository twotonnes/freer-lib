#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [set r:set])
             freer-lib))

@(define lens-eval (make-base-eval))
@interaction-eval[#:eval lens-eval (require freer-lib)]

@section{Core Lens}

@defmodule[freer-lib/lens/lens]

This module provides the core lens abstraction — a composable pair of @emph{get}
and @emph{set} functions that enables focused, immutable access into nested
data structures.

@defstruct[lens ([get procedure?] [set procedure?]) #:transparent]{
  A first-class lens value pairing a getter and a setter.

  @itemlist[
    @item{@racket[get]: A procedure @racket[(-> structure? any/c)] that extracts
          a focused value from a structure.}
    @item{@racket[set]: A procedure @racket[(-> any/c structure? structure?)] that
          returns a new structure with the focused value replaced.}
  ]

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
  A syntactic shorthand for chaining multiple @racket[set] operations on a single
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

@defproc[(over-l [l lens?] [update-fn procedure?] [structure any/c]) any/c]{
  Applies @racket[update-fn] to the focused value inside @racket[structure] and
  returns the updated structure. Equivalent to
  @racket[(set-l l (update-fn (view-l l structure)) structure)].

  @examples[#:eval lens-eval
    (over-l first-lens add1 '(10 20 30))
  ]
}

@defform[(lens-compose l1 l2 ...)]{
  Composes two or more lenses left-to-right, where @racket[l1] focuses @emph{inside}
  the target of @racket[l2]. The resulting lens focuses on the value that @racket[l1]
  would see after @racket[l2] has zoomed in.

  @examples[#:eval lens-eval
    (define nested '((1 2) (3 4)))

    (define inner-first-of-second
      (lens-compose first-lens second-lens))

    (view-l inner-first-of-second nested)
    (set-l  inner-first-of-second 99 nested)
  ]
}
