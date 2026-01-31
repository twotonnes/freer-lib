#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@title{Nothing Effect}

The nothing effect is a placeholder effect that represents a computation that has no result. It's useful for sequencing effects that matter only for their side effects.

@section{Purpose}

The nothing effect is used for:
@itemlist[
  @item{Effects that perform I/O or side effects but produce no meaningful result}
  @item{Chaining effects together where intermediate results don't matter}
  @item{Placeholder computations in effect handlers}
]

@section{API}

@defproc[(nothing) (Eff Any)]{
  Creates a nothing effect. This effect produces no useful result and is typically used when you only care about effects, not their return value.
}

@section{Example}

@codeblock{
  (with-effect-handlers
    ([(nothing-effect) (return #f)])
    (do (nothing)
        (nothing)
        (return "done")))
}

This executes two nothing effects and returns @racket["done"].

@section{Use Cases}

The nothing effect is commonly used in effect handlers where you only care about side effects:

@codeblock{
  ;; Logging operations often use nothing
  (do (log "Starting")
      (log "Processing")
      (log "Done")
      (return "result"))
}

In the above, each @racket[log] operation produces a nothing effect, but the computation flow is clear.

@section{Comparison with Plain Expressions}

In @racket[do]-notation, you can sequence effects without results:

@codeblock{
  ;; These are equivalent:
  (do (nothing)
      (return "result"))
  
  (do (effect-with-no-result)
      (return "result"))
}

The nothing effect makes the intent explicit: this operation has no meaningful result.
