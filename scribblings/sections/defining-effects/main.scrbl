#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{Defining Effects}

This section explains how to create your own custom effects and handlers to extend the effect-lib library for your specific use cases.

@include-section{basics.scrbl}
@include-section{example-state.scrbl}
@include-section{example-logging.scrbl}
@include-section{advanced-patterns.scrbl}
@include-section{best-practices.scrbl}