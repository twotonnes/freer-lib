#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [set r:set])
             freer-lib))

@(define iso-eval (make-base-eval))
@interaction-eval[#:eval iso-eval (require freer-lib)]

@title{Isomorphisms}

@defmodule[freer-lib/iso/main]

An isomorphism (or @emph{iso}) is a pair of conversion procedures between two representations of the same data, where each procedure is the inverse of the other.

@defstruct*[iso ([to-proc (-> any/c any/c)] [from-proc (-> any/c any/c)])]{
  An isomorphism between two representations.
  @itemlist[
    @item{@racket[to-proc]: Converts from the source representation to the target representation.}
    @item{@racket[from-proc]: Converts from the target representation back to the source representation.}
  ]

  @examples[#:eval iso-eval
    (define string<->number
      (iso string->number number->string))
  ]
}

@defproc[(iso-to [i iso?] [d any/c]) any/c]{
  Converts @racket[d] to the target representation using the @racket[to-proc] of @racket[i].

  @examples[#:eval iso-eval
    (iso-to string<->number "42")
  ]
}

@defproc[(iso-from [i iso?] [d any/c]) any/c]{
  Converts @racket[d] back to the source representation using the @racket[from-proc] of @racket[i].

  @examples[#:eval iso-eval
    (iso-from string<->number 42)
  ]
}

@defproc[(iso->lens [i iso?]) lens?]{
  Converts @racket[i] to a lens that views a structure in the source representation as its target representation. Setting a value through the lens ignores the original structure and returns the new value converted back with the @racket[from-proc] of @racket[i].

  @examples[#:eval iso-eval
    (define number-lens (iso->lens string<->number))

    (view-l number-lens "42")
  ]
}
