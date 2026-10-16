#lang racket/base

(provide
 string->free-jsexpr)

(require
 racket/match
 json
 "../freer-monad.rkt"
 "../effects/main.rkt")

;; Type: (-> String [(U 'dbg 'inf 'err)] Free)
(define (string->free-jsexpr str [log-level 'err])
  (with-handlers ([exn:fail? (lambda (exn)
                               (do-m
                                (match log-level
                                  ['err (log-err (format "can't deserialize string as jsexpr: ~a. String: ~s" (exn-message exn) str))]
                                  ['inf (log-inf (format "can't deserialize string as jsexpr: ~a. String: ~s" (exn-message exn) str))]
                                  ['dbg (log-dbg (format "can't deserialize string as jsexpr: ~a. String: ~s" (exn-message exn) str))])
                                (abort)))])
    (return (string->jsexpr str))))


(module+ test
  (require
   rackunit
   "../freer-monad.rkt"
   "../effects/main.rkt")

  (define (recording-handler logs)
    (lambda (eff k)
      (match eff
        [(log-effect level message)
         (set-box! logs (cons (cons level message) (unbox logs)))
         (k (void))]
        [(abort-effect) (return 'aborted)]
        [_ (error (format "the effect handler was called with ~v" eff))])))

  (test-case "string->free-jsexpr: should return the parsed value when the string is valid JSON"
    ;; Given
    (define logs (box '()))

    ;; When
    (define result
      (run (string->free-jsexpr "{\"a\":1}")
           (recording-handler logs)))

    ;; Then
    (check-equal? result (hasheq 'a 1))
    (check-equal? (unbox logs) '()))

  (test-case "string->free-jsexpr: should log at ERROR and abort when the string is invalid and the level is 'err"
    ;; Given
    (define logs (box '()))

    ;; When
    (define result
      (run (string->free-jsexpr "{bad" 'err)
           (recording-handler logs)))

    ;; Then
    (check-equal? result 'aborted)
    (check-equal? (map car (unbox logs)) '(ERROR))
    (check-regexp-match #rx"can't deserialize" (cdr (car (unbox logs)))))

  (test-case "string->free-jsexpr: should log at INFO and abort when the string is invalid and the level is 'inf"
    ;; Given
    (define logs (box '()))

    ;; When
    (define result
      (run (string->free-jsexpr "{bad" 'inf)
           (recording-handler logs)))

    ;; Then
    (check-equal? result 'aborted)
    (check-equal? (map car (unbox logs)) '(INFO)))

  (test-case "string->free-jsexpr: should raise an error when the log level is unknown and the string is invalid"
    (check-exn exn:fail?
               (lambda ()
                 (run (string->free-jsexpr "{bad" 'trace)
                      (recording-handler (box '()))))))

  (test-case "string->free-jsexpr: should log at DEBUG and abort when the string is invalid and the level is 'dbg"
    ;; Given
    (define logs (box '()))

    ;; When
    (define result
      (run (string->free-jsexpr "{bad" 'dbg)
           (recording-handler logs)))

    ;; Then
    (check-equal? result 'aborted)
    (check-equal? (map car (unbox logs)) '(DEBUG))))
