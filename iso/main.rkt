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
     (iso-from-proc new-value))))
