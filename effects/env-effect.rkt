#lang racket/base

(provide
 (record-out read-env-effect)
 read-env)

(require
 racket/contract
 rebellion/type/record
 rebellion/collection/record
 "../freer-monad.rkt")

(define-record-type read-env-effect (kw))

(define/contract (read-env kw)
  (-> any/c free?)
  (perform (read-env-effect #:kw kw)))
