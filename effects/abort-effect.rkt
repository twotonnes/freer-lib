#lang racket/base

(provide
  (struct-out abort-effect)
  abort)

(require
  racket/contract
  "../freer-monad.rkt")
  
(struct abort-effect ())

(define/contract (abort)
  (-> free?)
  (perform (abort-effect)))