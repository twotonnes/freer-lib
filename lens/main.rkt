#lang racket/base

(provide
 (all-from-out "lens.rkt")
 (all-from-out "common-lenses.rkt")
 (all-from-out "struct-lens.rkt"))

(require
 "lens.rkt"
 "common-lenses.rkt"
 "struct-lens.rkt")


;; struct/lens-out is tested here rather than in struct-lens.rkt: its test needs a
;; module that requires struct-lens.rkt, and a module inside struct-lens.rkt would cycle.
(module+ test
  (require rackunit)

  (module struct-lens-out-provider racket/base
    (require (only-in "struct-lens.rkt" struct/lens struct/lens-out))
    (struct/lens pair2 (left right) #:transparent)
    (provide (struct/lens-out pair2)))

  (require (submod "." struct-lens-out-provider))

  (test-case "struct/lens-out: should export the struct, its accessors, and its lenses"
    ;; When / Then
    (check-equal? (pair2-left (pair2 1 2)) 1)
    (check-equal? (view-l pair2->right (pair2 1 2)) 2)
    (check-equal? (set-l pair2->left 9 (pair2 1 2)) (pair2 9 2))))
