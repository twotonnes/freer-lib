#lang scribble/manual

@(require
  (for-label (rename-in racket [do r:do] [set r:set])
             freer-lib))

@title{Lenses}

@defmodule[freer-lib/lens/main]

This section documents the lens system — a composable, purely functional
approach to focusing on and updating values inside nested data structures.
The @racketmodname[freer-lib/lens/main] module re-exports all of the modules
described below.

@local-table-of-contents[]

@include-section["core.scrbl"]
@include-section["common.scrbl"]
@include-section["struct.scrbl"]