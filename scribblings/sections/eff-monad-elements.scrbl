#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define eff-monad-eval (make-base-eval))
@interaction-eval[#:eval eff-monad-eval
                  (require racket/base effect-lib)]

@title{Eff Monad Elements}

@section{Core Types}

@defthing[effect-desc]{
  The base descriptor for effects. This is an extensible struct that serves as the parent type for specific effect descriptors. Subclass this struct to represent particular types of effects.
}

@defthing[pure]{
  Represents a pure value in the effects monad—a computation that has no effects and directly produces a result.
  
  This is constructed using @racket[(pure value)].
}

@defthing[effect]{
  Represents an effect waiting to be handled. An effect structure contains:
  
  @itemlist[
    @item{@racket[description] - an @racket[effect-desc] that identifies and describes the type of effect.}
    @item{@racket[k] - a continuation (a function) that will receive the effect's result and return another effectful computation.}
  ]
  
  This is constructed using @racket[(effect description-value continuation-function)].
}

@section{Core Functions}

@defproc[(return [v any/c]) any/c]{
  Wraps a pure value into the Eff monad.
  
  This is the @emph{return} or @emph{pure} operation of the monad. It represents a computation that has no effects and immediately produces the given value.
}

@defproc[(run [m any/c] [handle (-> any/c any/c)]) any/c]{
  Interprets an effectful computation by repeatedly applying a handler until a pure value is obtained.
  
  The @racket[handle] function is called each time an @racket[effect] is encountered. It receives the effect structure and should return another effectful computation—either a pure result, or another effect to be handled.
}

@section{Monadic Operations}

@defproc[(>>= [m any/c] [f (-> any/c any/c)]) any/c]{
  Monadic bind operation (pronounced "bind"). Sequences two effectful computations together.
  
  @itemlist[
    @item{If @racket[m] is a @racket[pure] value, @racket[f] is applied to that value, yielding the next computation.}
    @item{If @racket[m] is an @racket[effect], a new effect is created with the same description but a new continuation that threads the result through @racket[f].}
  ]
}