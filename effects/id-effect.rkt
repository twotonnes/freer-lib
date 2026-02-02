#lang racket/base

(provide
  (struct-out id-effect)
  id)

(require "../eff-monad.rkt")

(struct id-effect effect-desc (value) #:transparent)

(define (id v)
    (effect (id-effect v) return))