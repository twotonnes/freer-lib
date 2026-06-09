#lang racket/base

(provide
  (struct-out rnd-effect)
  rnd
  do-rnd)

(require
  racket/contract
  "../freer-monad.rkt")

(struct rnd-effect (min max) #:transparent)

(define/contract (rnd min max)
  (-> exact-integer? exact-integer? free?)
  (perform (rnd-effect min max)))

(define/contract (do-rnd min max)
  (-> exact-integer? exact-integer? exact-integer?)
  (random min max))
