#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             effect-lib))

@(define nothing-eval (make-base-eval))
@interaction-eval[#:eval nothing-eval (require (rename-in racket [do racket:do]) effect-lib)]

@title{The Nothing Effect}

@defmodule[effect-lib/effects/nothing-effect]

@defstruct[(nothing-effect effect-desc) () #:transparent]{
  An effect descriptor representing the absence of a value or a specific "no-op" signal. 
}

@defproc[(nothing) effect?]{
  Creates a nothing effect.

  @examples[#:eval nothing-eval
    ;; A safe division function that returns 'nothing' on division by zero
    (define (safe-div x y)
      (if (zero? y)
          (nothing)
          (return (/ x y))))
    
    (define (calc-ratio a b)
      (do [res <- (safe-div a b)]
          (return (format "Ratio is ~a" res))))
  ]
}

This effect is often used by handlers of other effects to signal failure or early termination without crashing the entire program, effectively replacing a typed result with "nothing". 

When handling this effect, it is common to either abort the computation or resume with a default value (like @racket[(void)] or @racket[#f]).

@examples[#:eval nothing-eval
  ;; Strategy 1: Recover with a default value (Resume)
  (with-effect-handlers
    ([(nothing-effect) (return 0.0)]) ;; Treat failure as 0.0
    (calc-ratio 10 0))

  ;; Strategy 2: Abort the entire computation
  (with-effect-handlers
    ([(nothing-effect) (abort "Calculation failed")])
    (calc-ratio 10 0))
]
