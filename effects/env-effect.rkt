#lang racket/base

(provide
 (record-out read-env-effect)
 read-env)

(require
 rebellion/type/record
 rebellion/collection/record
 "../freer-monad.rkt")

(define-record-type read-env-effect (kw))

;; Type: (-> Any Free)
(define (read-env kw)
  (perform (read-env-effect #:kw kw)))


(module+ test
  (require
    rackunit
    "../freer-monad.rkt")

  (test-case "read-env: should perform a read-env-effect that carries the keyword"
    ;; Given
    (define computation (read-env 'HOME))

    ;; When
    (define effect (run computation (lambda (eff k) (return eff))))

    ;; Then
    (check-true (read-env-effect? effect))
    (check-equal? (read-env-effect-kw effect) 'HOME)))
