#lang scribble/manual

@(require
  (for-label (rename-in racket [do r:do])
             freer-lib))

@title{State}

@defmodule[freer-lib/effects/state-effect]

This module provides effects for a key-value store. The caller owns the store, a mutable hash, and reads and writes it through effects. The library ships only the effect descriptions and helpers. It ships no handler: the user writes one that answers @racket[read-state-effect] and @racket[write-state-effect] descriptions against the store, as with the environment effect. What happens when a key is missing is decided by the handler, not by the library.

@defstruct*[read-state-effect ([key any/c]) #:transparent]{
  The description of a read of @racket[key]. A handler receives it. Fields are accessed with @racket[read-state-effect-key].
}

@defstruct*[write-state-effect ([key any/c]
                                [value any/c]) #:transparent]{
  The description of a write of @racket[value] under @racket[key]. A handler receives it. Fields are accessed with @racket[write-state-effect-key] and @racket[write-state-effect-value].
}

@defproc[(read-state [key any/c]) free?]{
  Type: @racket[(-> Any Free)]. Describes the effect @racket[read-state-effect]: a read of the value of @racket[key] from the store. The computation's result is whatever the handler resumes with.
}

@defproc[(write-state [key any/c] [value any/c]) free?]{
  Type: @racket[(-> Any Any Free)]. Describes the effect @racket[write-state-effect]: a write of @racket[value] under @racket[key]. The result is @racket[(void)] when the handler answers the write with @racket[(void)], as the example handler below does.
}

@defproc[(update-state [key any/c] [f (-> any/c any/c)]) free?]{
  Type: @racket[(-> Any (-> Any Any) Free)]. Reads @racket[key], then writes @racket[(f value)] under it. Built from @racket[read-state] and @racket[write-state], so it describes both of their effects. @racket[f] is only called when the computation runs.
}

@defproc[(make-state-store [seed (listof pair?) '()]) hash?]{
  Type: @racket[(->* () ((Listof (Pairof Any Any))) Any)]. Impure: allocates and mutates a store. Returns a new mutable @racket[hasheq] holding the key/value pairs of @racket[seed]. Raises @racket[exn:fail] with a message naming the key when @racket[seed] repeats a key. Keys are compared with @racket[eq?], so equal strings are the same key only when they are the same object.
}

@bold{Example handler.} This one is an example of a handler a user could write. It raises on a missing key.

@racketblock[
(define ((state-handler! store) desc k)
  (cond
    [(read-state-effect? desc) (k (hash-ref store (read-state-effect-key desc)))]
    [(write-state-effect? desc)
     (hash-set! store (write-state-effect-key desc) (write-state-effect-value desc))
     (k (void))]
    [else (error "unexpected effect")]))

(define store (make-state-store '((n . 0))))
(run (>>= (update-state 'n add1)
          (lambda (_) (read-state 'n)))
     (state-handler! store))
]
