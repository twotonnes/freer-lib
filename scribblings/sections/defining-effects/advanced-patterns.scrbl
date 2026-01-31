#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{Advanced Patterns}

@section{Aborting Early}

The @racket[abort] form in @racket[with-effect-handlers] allows you to short-circuit computation and return a pure result without invoking the continuation:

@codeblock{
  (struct error-effect (effect-desc)
    [message : String] #:transparent)
  
  (: raise-error (-> String (Eff Any)))
  (define (raise-error msg)
    (effect (error-effect msg)
            (lambda (_) (return (void)))))
  
  (: run-with-errors (All (A) (-> (Eff A) (U A String))))
  (define (run-with-errors m)
    (with-effect-handlers
      ([(error-effect msg) (abort msg)])
      m))
}

When an error is encountered, it aborts the computation and returns the error message instead of continuing.

@section{Composing Effects}

Multiple effects can be handled by a single @racket[with-effect-handlers] form:

@codeblock{
  (with-effect-handlers
    ([(state-get)
      (return (unbox state))]
     [(state-set val)
      (set-box! state val)
      (return (void))]
     [(log-msg msg)
      (set-box! logs (cons msg (unbox logs)))
      (return (void))])
    computation)
}

@section{Nested Handlers}

Handlers can be nested to layer different effect interpretations:

@codeblock{
  (with-effect-handlers
    ([(outer-effect data) ...])
    (with-effect-handlers
      ([(inner-effect data) ...])
      computation))
}

The innermost handler processes effects first. If it doesn't handle an effect (by letting it propagate), the outer handler gets a chance.

@section{Creating Custom Interpreters}

For complex scenarios, you can create custom interpreters that combine effect handling with other logic:

@codeblock{
  (: run-counting-effects (All (A) (-> (Eff A) (Values A Natural))))
  (define (run-counting-effects m)
    (define count (box 0))
    (define result
      (with-effect-handlers
        ([(my-effect param)
          (set-box! count (+ 1 (unbox count)))
          (return "handled")])
        m))
    (values result (unbox count)))
}

This interpreter tracks how many effects were executed during computation.

@section{Re-running Computations}

Because effects are separated from their handlers, you can run the same computation with different strategies:

@codeblock{
  (define computation
    (do [x <- (get-state)]
        (log (format "State is: ~a" x))
        [y <- (get-state)]
        (return (+ x y))))
  
  ;; Try different handlers
  (define result1 (run-state computation 10))
  (define result2 (run-silently computation))
  (define-values (result3 logs) (run-with-logging computation))
}

This is powerful for testing and exploring different effect implementations without rewriting code.
