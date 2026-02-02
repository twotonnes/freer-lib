#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval (require effect-lib racket/match)]

@title{Syntactic Forms}

To simplify the composition of effects and the definition of handlers, the library provides standard syntactic sugar.

@defform[(do clause ...)
         #:grammar ([clause (code:line [id <- expr])
                            (code:line expr)])]{
  A monadic sequencing macro similar to Haskell's do-notation. It expands into nested calls to @racket[>>=].

  @itemlist[
    @item{@racket[[id <- expr]]: Executes @racket[expr]. The result is unpacked and bound to @racket[id] for the scope of the remaining clauses. Binding happens through @racket[match], which means that @italic{id} must take the form of a @racket[match] clause.}
    @item{@racket[expr]: Executes @racket[expr] for its side effects, ignoring its result (binding it to @racket[_]), and proceeds to the next clause.}
  ]
  
  The final expression in the sequence dictates the return value of the whole @racket[do] block.

  @examples[#:eval effect-lib-eval
    ;; Define a basic "Ask" effect
    (struct ask (question))
    (define (ask-user q) (effect (ask q) return))

    ;; A computation that asks two questions and combines the results
    (define survey-computation
      (do [name <- (ask-user "What is your name?")]
          [age  <- (ask-user "What is your age?")]
          (return (format "~a is ~a years old." name age))))
    
    ;; Verify the sequencing (assuming a handler that provides fixed inputs)
    (with-effect-handlers
      ([(ask "What is your name?") (return "Alice")]
       [(ask "What is your age?") (return 30)])
      survey-computation)
  ]
}

@defform[(with-effect-handlers (handler-clause ...) body ...)
         #:grammar ([handler-clause [pattern handler-body ...+]
                                    [pattern handler-body ... (abort result-expr)]])]{
  Runs the code in @racket[body ...] within a context that handles effects matching the provided patterns. This macro expands to a call to @racket[run].

  The @racket[handler-clause]s use @racket[match] syntax to destructure the effect descriptor. The implicit effect object (containing the descriptor and continuation) is available to the macro expansion but hidden from the user syntax to streamline code.

  There are two types of handler clauses:
  
  @itemlist[
    @item{**Resuming Handlers**: By default, the result of the @racket[handler-body] is passed to the effect's continuation @racket[k]. The computation then proceeds via @racket[>>=].}
    
    @item{**Aborting Handlers**: If the clause ends with @racket[(abort result-expr)], the computation is short-circuited. The continuation @racket[k] is discarded, and @racket[result-expr] (wrapped in @racket[pure]) becomes the final result of the handled block.}
  ]

  If an effect is raised that does not match any clause, an error is raised.

  @examples[#:eval effect-lib-eval
    (struct log (message))
    (struct crash (reason))

    (define (log-msg m) (effect (log m) return))
    (define (fail r) (effect (crash r) return))

    ;; A handler that handles logging (resumes) and crashing (aborts)
    (with-effect-handlers
      ([(log m) 
        (displayln m)     ;; Side effect in the handler
        (return (void))]  ;; Resume computation with void
        
        [(crash reason)
        (displayln (format "System aborted: ~a" reason))
        (abort 'failed)]) ;; Abort and return 'failed
      
      (do (log-msg "Starting process...")
          (log-msg "Process running...")
          (fail "Critical Error")
          (log-msg "This will never be printed")))
  ]
}
