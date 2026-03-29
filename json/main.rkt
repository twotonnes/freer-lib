#lang racket/base

(provide
 string->free-jsexpr)

(require
 racket/contract
 racket/match
 json
 "../freer-monad.rkt"
 "../effects/main.rkt")

(define/contract (string->free-jsexpr str [log-level 'err])
  (-> string? (symbols 'dbg 'inf 'err) free?)
  (with-handlers ([exn:fail? (lambda (exn)
                               (do-m
                                (match log-level
                                  ['err (log-err (format "can't deserialize string as jsexpr: ~a. String: ~s" (exn-message exn) str))]
                                  ['inf (log-inf (format "can't deserialize string as jsexpr: ~a. String: ~s" (exn-message exn) str))]
                                  ['dbg (log-dbg (format "can't deserialize string as jsexpr: ~a. String: ~s" (exn-message exn) str))])
                                (abort)))])
    (return (string->jsexpr str))))
