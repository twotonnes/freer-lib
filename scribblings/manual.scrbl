#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [log-info r:log-info] [log-debug r:log-debug] [log-error r:log-error])
             freer-lib))

@title{Algebraic Effects}

@defmodule[freer-lib]

This library implements a lightweight system for extensible algebraic effects. It allows computations to perform effectful operations that are decoupled from their implementations. The system is built around a free monad structure where computations are represented as sequences of suspended effects.

@local-table-of-contents[]

@include-section["eff-monad/core.scrbl"]
@include-section["eff-monad/syntax.scrbl"]
@include-section["effects/overview.scrbl"]