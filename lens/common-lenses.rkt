#lang racket/base

(provide (all-defined-out))

(require
 (for-syntax racket/base
             racket/syntax)
 "lens.rkt")

(define (hash-lens key)
  (lens
   (lambda (h) (hash-ref h key))
   (lambda (new-v h) (hash-set h key new-v))))

(define-syntax (struct-lens stx)
  (syntax-case stx ()
    [(_ id field-id)
     (with-syntax ([accessor (format-id #'field-id "~a-~a" #'id #'field-id)])
       #'(lens
          accessor
          (lambda (new-v s) (struct-copy id s [field-id new-v]))))]))
