#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [log-info r:log-info] [log-debug r:log-debug] [log-error r:log-error])
             freer-lib))

@(define freer-lib-eval (make-base-eval))
@interaction-eval[#:eval freer-lib-eval (require freer-lib racket/match)]

@title{Syntactic Forms}

To simplify the composition of impures, the library provides standard syntactic sugar.

@defform[(do clause ...)
         #:grammar ([clause (code:line [id <- expr])
                            (code:line expr)])]{
  A monadic sequencing macro similar to Haskell's do-notation. It expands into nested calls to @racket[>>=].

  @itemlist[
    @item{@racket[[id <- expr]]: Executes @racket[expr]. The result is unpacked and bound to @racket[id] for the scope of the remaining clauses. Binding happens through @racket[match], which means that @italic{id} must take the form of a @racket[match] clause.}
    @item{@racket[expr]: Executes @racket[expr] for its side impures, ignoring its result (binding it to @racket[_]), and proceeds to the next clause.}
  ]
  
  The final expression in the sequence dictates the return value of the whole @racket[do] block.

  @examples[#:eval freer-lib-eval
    ;; Define a basic "Ask" impure
    (struct ask (question))
    (define (ask-user q) (impure (ask q) return))

    ;; A computation that asks two questions and combines the results
    (define survey-computation
      (do [name <- (ask-user "What is your name?")]
          [age  <- (ask-user "What is your age?")]
          (return (format "~a is ~a years old." name age))))
    
    ;; Verify the sequencing with a handler
    (run survey-computation
         (lambda (eff k)
           (match eff
             [(ask "What is your name?") (k "Alice")]
             [(ask "What is your age?") (k 30)])))
  ]
}