#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{Example: State Effect}

A state effect allows you to read and modify a mutable state in a purely functional way. Here's a complete example:

@section{Defining the Effect Descriptor}

@codeblock{
  (struct state-get (effect-desc) #:transparent)
  (struct state-set (effect-desc)
    [value : Any] #:transparent)
}

These two structures represent getting and setting state.

@section{Effect Operations}

Create helper functions to construct effects:

@codeblock{
  (: get-state (-> (Eff Any)))
  (define (get-state)
    (effect (state-get)
            (lambda (state) (return state))))
  
  (: set-state (All (A) (-> A (Eff Void))))
  (define (set-state new-state)
    (effect (state-set new-state)
            (lambda (_) (return (void)))))
}

@section{Running with State}

To run stateful computations, create a handler that manages the state through a mutable cell or parameter:

@codeblock{
  (: run-state (All (A) (-> (Eff A) Any A)))
  (define (run-state m initial-state)
    (define state (box initial-state))
    (with-effect-handlers
      ([(state-get)
        (return (unbox state))]
       [(state-set new-val)
        (set-box! state new-val)
        (return (void))])
      m))
}

@section{Usage}

@examples[
  #:eval effect-lib-eval
  (run-state
    (do [x <- (get-state)]
        (set-state (+ x 1))
        [y <- (get-state)]
        (return y))
    10)
]

This example starts with state 10, increments it by 1, and returns the new state.
