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


(module+ test
  (require
    rackunit
    "../freer-monad.rkt")

  (test-case "failure: should perform a failure-effect with the message"
    (check-match (failure "boom") (impure (failure-effect "boom") _))))
