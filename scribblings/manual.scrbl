#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{Effect Lib}

@defmodule[effect-lib]

The @racketmodname[effect-lib] library provides a typed, extensible effects monad for Racket. This approach allows you to separate the @emph{description} of side effects from their @emph{execution}, enabling flexible effect handling strategies and easier testing and composition of effectful code.

@local-table-of-contents[]

@include-section{sections/overview.scrbl}
@include-section{sections/types-and-structures/main.scrbl}
@include-section{sections/monadic-operations/main.scrbl}
@include-section{sections/syntactic-sugar/main.scrbl}
@include-section{sections/built-in-effects/main.scrbl}
@include-section{sections/defining-effects/main.scrbl}