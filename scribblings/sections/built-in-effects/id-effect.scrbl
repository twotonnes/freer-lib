#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@title{Identity Effect}

The identity effect is the simplest possible effect. It wraps a value and does nothing with it, making it useful for testing and understanding the monad structure.

@section{Purpose}

The identity effect is primarily used for:
@itemlist[
  @item{Understanding the effect monad structure without complexity}
  @item{Testing effect handlers with minimal setup}
  @item{Demonstrating monadic composition}
]

@section{API}

@defproc[(id [v A]) (Eff Any)]{
  Creates an identity effect wrapping the value @racket[v]. The effect simply passes the value through without any side effects.
}

@section{Example}

@codeblock{
  (with-effect-handlers
    ([(id-effect v) (return v)])
    (do [x <- (id "hello")]
        (return x)))
}

This returns @racket["hello"].

@section{Practical Use}

While simple, the identity effect demonstrates fundamental monadic patterns:

@codeblock{
  ;; Sequencing multiple pure operations
  (do [x <- (id 1)]
      [y <- (id 2)]
      (return (+ x y)))
}

The identity effect is useful for writing tests that verify monadic sequencing without involving real effects:

@codeblock{
  ;; Test that a computation chains correctly
  (define test-result
    (with-effect-handlers
      ([(id-effect v) (return v)])
      (do [x <- (id 10)]
          [y <- (id 20)]
          (return (+ x y)))))
  
  (assert (= test-result 30))
}
