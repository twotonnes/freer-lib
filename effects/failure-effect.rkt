#lang racket/base

(provide
  (struct-out failure-effect)
  failure)

(require
  racket/contract
  "../freer-monad.rkt")
  
(struct failure-effect (msg))

(define/contract (failure msg)
  (-> string? free?)
  (perform (failure-effect msg)))
