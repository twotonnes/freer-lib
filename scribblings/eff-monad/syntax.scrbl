#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define freer-lib-eval (make-base-eval))
@interaction-eval[#:eval freer-lib-eval (require freer-lib racket/match)]

@title{Syntactic Forms}

To simplify the composition of effectful computations, the library provides standard syntactic sugar.

@defform[(do-m clause ... final-expr)
         #:grammar ([clause (code:line [pattern <- expr])
                            (code:line expr)])
         #:contracts ([expr free?]
                      [final-expr free?])]{
  A monadic sequencing macro similar to Haskell's do-notation. It expands into nested calls to @racket[>>=].

  @itemlist[
    @item{@racket[[pattern <- expr]]: Runs the computation @racket[expr] and matches its result against @racket[pattern] using @racket[match]. The variables bound by @racket[pattern] are in scope for the remaining clauses. If the result does not match @racket[pattern], a @racket[match] error is raised.}
    @item{@racket[expr]: Runs the computation @racket[expr] for its effects, ignoring its result, and proceeds to the next clause.}
  ]

  The last form, @racket[final-expr], must be a plain expression (not a binding clause); its computation dictates the result of the whole @racket[do-m] block.

  @examples[#:eval freer-lib-eval
    (code:comment "Define a basic \"ask\" effect")
    (struct ask (question))
    (define (ask-user q) (perform (ask q)))

    (code:comment "A computation that asks two questions and combines the results")
    (define survey-computation
      (do-m [name <- (ask-user "What is your name?")]
            [age  <- (ask-user "What is your age?")]
            (return (format "~a is ~a years old." name age))))

    (code:comment "Verify the sequencing with a handler")
    (run survey-computation
         (lambda (eff k)
           (match eff
             [(ask "What is your name?") (k "Alice")]
             [(ask "What is your age?") (k 30)])))

    (code:comment "Bindings can destructure their result")
    (run (do-m [(list a b) <- (return (list 10 20))]
               (return (+ a b)))
         (lambda (eff k) (k eff)))
  ]
}
