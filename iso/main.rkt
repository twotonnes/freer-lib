#lang racket/base

(provide (all-defined-out))

(require
 "../lens/main.rkt")

(struct iso (to-proc from-proc))

(define (iso-to i d)
  ((iso-to-proc i) d))

(define (iso-from i d)
  ((iso-from-proc i) d))

(define (iso->lens i)
  (lens
   (iso-to-proc i)
   (lambda (new-value structure)
     ((iso-from-proc i) new-value))))


(module+ test
  (require
   rackunit
   "../lens/main.rkt")

  (define double (iso (lambda (x) (* 2 x)) (lambda (y) (/ y 2))))

  (test-case "iso-to: should apply the to-procedure"
    (check-equal? (iso-to double 3) 6))

  (test-case "iso-from: should apply the from-procedure"
    (check-equal? (iso-from double 6) 3))

  (test-case "iso: should return the original value after a round trip"
    (check-equal? (iso-from double (iso-to double 5)) 5))

  (test-case "iso->lens: should view the to-value of the structure"
    (check-equal? (view-l (iso->lens double) 3) 6))

  (test-case "iso->lens: should set the from-value of the new value and ignore the old structure"
    (check-equal? (set-l (iso->lens double) 8 'ignored-structure) 4)))
