#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{Basic Concepts}

To define a custom effect, you need to:

@itemlist[
  @item{Create an @racket[effect-desc] subclass to represent your effect type,}
  @item{Optionally store effect-specific data in the descriptor,}
  @item{Create a helper function that wraps the effect in an @racket[effect] structure,}
  @item{Write handlers to process your effects using @racket[with-effect-handlers].}
]

@section{Effect Descriptors}

An effect descriptor is a struct that extends @racket[effect-desc]. It serves as a tag and can carry data about the effect:

@codeblock{
  (struct my-effect (effect-desc)
    [parameter : String])
}

When your effect is handled, the descriptor allows pattern matching to identify it and access its data.

@section{Creating Effects}

Use @racket[effect] to wrap your effect descriptor with a continuation:

@codeblock{
  (define (my-effect-op param)
    (effect
      (my-effect param)
      (lambda (result)
        (return result))))
}

The continuation receives the result from the effect handler and returns another @racket[Eff] computation, allowing you to chain multiple effects together.

@section{Handling Effects}

Use @racket[with-effect-handlers] to define how effects are processed. Each handler pattern-matches on your effect descriptor and decides how to handle it:

@codeblock{
  (with-effect-handlers
    ([(my-effect param)
      (printf "Handling effect with: ~a~n" param)
      (return "result")])
    (do [result <- (my-effect-op "test")]
        (return result)))
}
