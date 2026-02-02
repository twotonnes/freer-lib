#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval (require effect-lib racket/match)]

@title{Core Effects API}

The core API defines the structure of effectful computations and the machinery to execute them.

@defstruct[pure ([value any/c]) #:transparent]{
  Represents a computation that has completed successfully with a result @racket[value]. This is the base case of the free monad.
}

@defstruct[effect ([description any/c]
                   [k (-> any/c any/c)]) #:transparent]{
  Represents a suspended computation waiting on an effect.
  @itemlist[
    @item{@racket[description]: The payload describing the requested effect.}
    @item{@racket[k]: The continuation function. It accepts the result of the effect and returns the next step of the computation.}
  ]
}

@defproc[(return [v any/c]) pure?]{
  Lifts a raw value @racket[v] into the effect context. This is equivalent to constructing @racket[(pure v)].

  @examples[#:eval effect-lib-eval
    (return 42)
  ]
}

@defproc[(>>= [m (or/c pure? effect?)]
               [f (-> any/c (or/c pure? effect?))])
         (or/c pure? effect?)]{
  Sequences two effectful computations. It applies the function @racket[f] to the result of @racket[m] once @racket[m] produces a value.
  
  If @racket[m] is a @racket[pure] value, @racket[f] is applied immediately. If @racket[m] is an @racket[effect], the binding is pushed down into the continuation @racket[k], creating a new computation that pauses for the same effect but runs @racket[f] after the original continuation completes.

  @examples[#:eval effect-lib-eval
    (struct increment ())
    
    ;; Manually chain a pure value into an effect
    (>>= (return 10)
         (lambda (x)
           (effect (increment) (lambda (res) (return (+ x res))))))
  ]
}

@defproc[(run [m (or/c pure? effect?)]
              [handle (-> effect? (or/c pure? effect?))])
         any/c]{
  Executes an effectful computation @racket[m] by repeatedly resolving effects using the provided @racket[handle] function.
  
  When @racket[run] encounters a @racket[pure] value, it returns the unwrapped value. When it encounters an @racket[effect], it passes the effect object to @racket[handle]. The handler is expected to resume the computation (usually by invoking the continuation inside the effect), returning a new state that @racket[run] will continue to process.

  @examples[#:eval effect-lib-eval
    (struct read-env (var-name))
    
    ;; A computation that asks for an environment variable
    (define my-computation
      (effect (read-env "HOME") 
              (lambda (path) (return (string-append "Home is: " path)))))
    
    ;; Running the computation with a manual handler function
    (run my-computation
         (lambda (eff)
           (match eff
             [(effect (read-env var) k)
              ;; Resume the continuation 'k' with a simulated value
              (k "/usr/home/racket-user")])))
  ]
}
