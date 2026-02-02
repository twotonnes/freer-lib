#lang racket/base

(provide
  (struct-out nothing-effect)
  nothing)

(require
  "../eff-monad.rkt")
  
(struct nothing-effect ())

(define (nothing)
  (effect (nothing-effect) return))