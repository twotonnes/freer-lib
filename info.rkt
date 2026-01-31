#lang info

;; 1. Define the collection name explicitly
(define collection "effect-lib")

;; 2. Register documentation
;; The path is relative to this info.rkt file
(define scribblings '(("scribblings/manual.scrbl" (multi-page))))

;; 3. Dependencies
(define deps '("base"))

;; 4. Build Dependencies
;; Tools needed only for docs/tests/etc.
(define build-deps '("scribble-lib" "racket-doc"))
