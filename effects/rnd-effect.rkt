#lang racket/base

(provide
  (struct-out rnd-effect)
  rnd)

(require
  racket/contract
  "../freer-monad.rkt")

(struct rnd-effect (min max) #:transparent)

(define/contract (rnd min max)
  (->i ([min exact-integer?]
        [max (min) (and/c exact-integer? (>=/c min))])
       [result free?])
  (perform (rnd-effect min max)))
