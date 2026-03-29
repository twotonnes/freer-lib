#lang racket/base

(provide
 string->free-jsexpr)

(require
 racket/contract
 json
 "../freer-monad.rkt"
 "../effects/main.rkt")

(define/contract (string->free-jsexpr str)
  (-> string? free?)
  (with-handlers ([exn:fail? (lambda (exn)
                               (do-m
                                (log-err (format "can't deserialize string as jsexpr: ~a. String: ~s"
                                                 (exn-message exn)
                                                 str))
                                (abort)))])
    (return (string->jsexpr str))))
