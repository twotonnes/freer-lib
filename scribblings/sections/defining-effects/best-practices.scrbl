#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@title{Best Practices}

@section{Naming Conventions}

Use clear, descriptive names for your effect descriptors and operations:

@itemlist[
  @item{Effect descriptors: Use verb-noun form like @racket[read-file], @racket[http-get], @racket[state-set]}
  @item{Operations: Use lowercase with hyphens, e.g., @racket[(read-file path)], @racket[(http-get url)]}
  @item{Descriptors: Typically match the operation name with @racket[-effect] suffix for clarity}
]

@section{Type Annotations}

Always provide complete type annotations for effect operations:

@codeblock{
  (: my-operation (-> String (Eff Integer)))
  (define (my-operation param)
    (effect (my-effect param)
            (lambda (result) (return result))))
}

This helps with type checking and makes your effect API clear to users.

@section{Documentation}

Document what your effects do, what parameters they accept, and what they return:

@codeblock{
  ;;; Reads a file and returns its contents.
  ;;; param path: The file path to read
  ;;; return: The file contents as a string
  (: read-file (-> String (Eff String)))
}

@section{Transparent Structures}

Use `#:transparent` when defining effect descriptors to make debugging easier:

@codeblock{
  (struct my-effect (effect-desc)
    [data : Any] #:transparent)
}

This allows printing and inspection of effect values during development.

@section{Handler Completeness}

Ensure all effects are handled by your handler, or provide a catch-all that explains what went wrong:

@codeblock{
  (with-effect-handlers
    ([(effect1 x) (return x)]
     [(effect2 y) (return y)])
    computation)
  ;; Error: Unhandled effect still gets a clear error message
}

@section{Avoiding Infinite Loops}

Be careful with handlers that re-invoke effects. Ensure your handler eventually terminates:

@codeblock{
  ;; WRONG: This creates infinite recursion
  (with-effect-handlers
    ([(my-effect x)
      (my-effect-operation)])  ;; Calls itself!
    computation)
  
  ;; RIGHT: Progress toward termination
  (with-effect-handlers
    ([(my-effect x)
      (return (process x))])   ;; Returns a value
    computation)
}

@section{Separation of Concerns}

Keep effect definitions, operations, and handlers in separate modules or at least separate sections:

@itemlist[
  @item{@bold{Definitions:} The struct definitions for effect descriptors}
  @item{@bold{Operations:} Functions that create effects}
  @item{@bold{Handlers:} Functions that interpret effects}
]

This makes code more modular and testable.

@section{Testing}

Test your effects by creating mock handlers:

@codeblock{
  ;;; Mock handler for testing without side effects
  (: mock-handler (All (A) (-> (Eff A) A)))
  (define (mock-handler m)
    (with-effect-handlers
      ([(my-effect x) (return (mock-result x))])
      m))
}

This allows you to test code that uses effects without performing actual I/O, state mutations, etc.
