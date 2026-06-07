#lang info

(define collection "freer-lib")
(define scribblings '(("scribblings/manual.scrbl" (multi-page))))
(define deps '("base" "gregor"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define pkg-desc "A collection of libraries for writing freer monads in Racket.")
(define pkg-authors '("Niels Nijholt"))
(define license "MIT")