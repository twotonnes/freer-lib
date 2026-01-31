#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require racket effect-lib)]

@title{Effect Lib}

@defmodule[effect-lib]

@section{Introduction}

The @racketmodname[effect-lib] library provides an extensible effects monad for Racket. This approach allows you to separate the @emph{description} of side effects from their @emph{execution}, enabling flexible effect handling strategies and easier testing and composition of effectful code.

@local-table-of-contents[]

@section{Documentation Overview}

This manual is divided into the following sections:

@itemlist[
]

@include-section{sections/eff-monad-elements.scrbl}