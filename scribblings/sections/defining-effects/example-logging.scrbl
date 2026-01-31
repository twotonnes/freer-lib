#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{Example: Logging Effect}

A logging effect allows you to accumulate log messages during computation, separating the logging intent from the output mechanism.

@section{Defining the Effect}

@codeblock{
  (struct log-msg (effect-desc)
    [message : String] #:transparent)
}

@section{Creating Log Operations}

@codeblock{
  (: log (-> String (Eff Void)))
  (define (log msg)
    (effect (log-msg msg)
            (lambda (_) (return (void)))))
}

@section{Running with Logging}

Create a handler that collects all log messages:

@codeblock{
  (: run-with-logging (All (A) (-> (Eff A) (Values A (Listof String)))))
  (define (run-with-logging m)
    (define logs (box '()))
    (define result
      (with-effect-handlers
        ([(log-msg msg)
          (set-box! logs (cons msg (unbox logs)))
          (return (void))])
        m))
    (values result (reverse (unbox logs))))
}

@section{Usage}

@codeblock{
  (define-values (result logs)
    (run-with-logging
      (do (log "Starting computation")
          [x <- (return 42)]
          (log (format "Got value: ~a" x))
          (return x))))
  
  (printf "Result: ~a~n" result)
  (printf "Logs: ~a~n" logs)
}

This separates the logging description (what to log) from the collection mechanism (how to collect it), making it easy to test code without worrying about output.

@section{Multiple Handlers}

You can define different handlers for different situations:

@codeblock{
  (: run-silently (All (A) (-> (Eff A) A)))
  (define (run-silently m)
    (with-effect-handlers
      ([(log-msg msg) (return (void))])
      m))
  
  (: run-with-printing (All (A) (-> (Eff A) A)))
  (define (run-with-printing m)
    (with-effect-handlers
      ([(log-msg msg) (displayln msg) (return (void))])
      m))
}

The same computation can run silently, print logs, or save them to a list—just by changing the handler.
