#lang racket/base

(provide
  (struct-out nothing-effect)
  nothing)

(require
  "../eff-monad.rkt")
  
(struct nothing-effect effect-desc ())

(define (nothing)
  (effect (nothing-effect) return))