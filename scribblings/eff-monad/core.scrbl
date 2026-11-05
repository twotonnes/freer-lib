#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [set r:set])
             freer-lib))

@(define freer-lib-eval (make-base-eval))
@interaction-eval[#:eval freer-lib-eval (require freer-lib racket/match)]

@title{Core Effects API}

The core API defines the structure of effectful computations and the machinery to execute them.

@defstruct[pure ([value any/c]) #:transparent]{
  Represents a computation that has completed successfully with a result @racket[value]. This is the base case of the free monad.
}

@defstruct[impure ([description any/c]
                   [k (-> any/c any/c)]
                   [queue any/c]) #:transparent]{
  Represents a suspended computation waiting on an effect.
  @itemlist[
    @item{@racket[description]: The payload describing the requested effect.}
    @item{@racket[k]: The continuation function. It accepts the result of the effect and returns the next step of the computation.}
    @item{@racket[queue]: The queue of pending continuations. Each @racket[>>=] appends its function to this queue instead of wrapping @racket[k].}
  ]
}

@defproc[(free? [m any/c]) boolean?]{
  Returns @racket[#t] if @racket[m] is either a @racket[pure] or @racket[impure] value, @racket[#f] otherwise. This is a type-checking predicate for the free monad.

  @examples[#:eval freer-lib-eval
    (free? (return 42))
    (free? (perform 'effect))
    (free? 42)
  ]
}

@defproc[(return [v any/c]) pure?]{
  Lifts a raw value @racket[v] into the effect context. This is equivalent to constructing @racket[(pure v)].

  @examples[#:eval freer-lib-eval
    (return 42)
  ]
}

@defproc[(perform [desc any/c]) free?]{
  Creates a waiting computation for the effect described by @racket[desc]. Its queue of pending continuations holds only @racket[return]. This is used to request an effect that should be handled by an effect handler.

  @examples[#:eval freer-lib-eval
    (perform 'read-value)
    (perform (list 'http-get "http://example.com"))
  ]
}

@defproc[(>>= [m free?]
              [f (-> any/c free?)])
         free?]{
  Sequences two effectful computations. It applies the function @racket[f] to the result of @racket[m] once @racket[m] produces a value.
  
  If @racket[m] is a @racket[pure] value, @racket[f] is applied immediately. If @racket[m] is an @racket[impure], @racket[f] is appended to the queue of pending continuations, creating a new computation that pauses for the same effect but runs @racket[f] after the continuations already pending.

  @examples[#:eval freer-lib-eval
    (struct increment ())
    
    ;; Chain a pure value into a waiting computation
    (>>= (return 10)
         (lambda (x)
           (>>= (perform (increment))
                (lambda (res) (return (+ x res))))))
  ]
}

@defproc[(sequence [l (listof free?)])
         free?]{
  Turns a list of effectful computations into a single computation that produces a list of their results, in the same order as @racket[l]. Each computation in @racket[l] runs in sequence: the next one starts only after the previous one has produced a value.

  @examples[#:eval freer-lib-eval
    (sequence (list (return 1) (return 2) (return 3)))
  ]
}

@defproc[(map-m [proc (-> any/c free?)]
                [l (listof any/c)])
         free?]{
  Applies @racket[proc] to each element of @racket[l] in order and collects the results into a list. Each application is an effectful computation, so effects are performed one element at a time, left to right. This is equivalent to composing @racket[sequence] with a @racket[map] of @racket[proc] over @racket[l], but it also works over effectful functions.

  @examples[#:eval freer-lib-eval
    (map-m (lambda (n) (return (* 2 n))) '(1 2 3))
  ]
}

@defproc[(run [m free?]
              [handle (-> any/c (-> any/c free?) free?)])
         any/c]{
  Executes an effectful computation @racket[m] by repeatedly resolving effects using the provided @racket[handle] function.
  
  When @racket[run] encounters a @racket[pure] value, it returns the unwrapped value. When it encounters an @racket[impure], it extracts the effect description and continuation, then passes them to @racket[handle] as separate arguments. The handler can process the effect and resume the computation by calling the continuation @racket[k], or it can return a new computation to continue execution.

  @examples[#:eval freer-lib-eval
    (struct read-home (var-name))
    
    ;; A computation that asks for an environment variable
    (define my-computation
      (do-m [path <- (perform (read-home "HOME"))]
          (return (string-append "Home is: " path))))
    
    ;; Running the computation with a handler
    (run my-computation
         (lambda (eff k)
           (match eff
             [(read-home var)
              ;; Resume the continuation 'k' with a simulated value
              (k "/usr/home/racket-user")])))
  ]
}
