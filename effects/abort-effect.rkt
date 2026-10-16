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

(module+ test
  (require
    rackunit
    racket/match
    "../freer-monad.rkt")

  (test-case "abort: should perform an abort-effect"
    (check-match (abort) (impure (abort-effect) _)))

  (test-case "abort: should stop the computation when the handler does not resume"
    ;; Given
    (define computation (do-m (abort) (return 1)))

    ;; When
    (define result
      (run computation
           (lambda (eff k)
             (match eff
               [(abort-effect) (return 'stopped)]))))

    ;; Then
    (check-equal? result 'stopped)))
