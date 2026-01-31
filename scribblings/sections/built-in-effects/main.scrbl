#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{Built-in Effects}

This section documents the pre-built effects that ship with effect-lib. These effects provide common functionality like executing commands and making HTTP requests.

@include-section{id-effect.scrbl}
@include-section{nothing-effect.scrbl}
@include-section{cmd-effect.scrbl}
@include-section{http-effect.scrbl}