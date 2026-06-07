#lang racket/base

(provide
  (struct-out id-effect)
  id)

(require
  racket/contract
  "../freer-monad.rkt")

(struct id-effect (value) #:transparent)

(define/contract (id v)
  (-> any/c free?)
  (perform (id-effect v)))