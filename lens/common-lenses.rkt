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


(module+ test
  (require rackunit)

  (struct person (name age) #:transparent)

  (test-case "hash-lens: should view the value stored under the key"
    (check-equal? (view-l (hash-lens 'a) (hash 'a 1 'b 2)) 1))

  (test-case "hash-lens: should set the value without changing the original hash"
    ;; Given
    (define original (hash 'a 1 'b 2))

    ;; When
    (define updated (set-l (hash-lens 'a) 10 original))

    ;; Then
    (check-equal? (hash-ref updated 'a) 10)
    (check-equal? (hash-ref updated 'b) 2)
    (check-equal? (hash-ref original 'a) 1))

  (test-case "hash-lens: should raise an error when the key is missing"
    (check-exn exn:fail? (lambda () (view-l (hash-lens 'missing) (hash 'a 1)))))

  (test-case "struct-lens: should view a field of a struct"
    (check-equal? (view-l (struct-lens person name) (person "Ann" 30)) "Ann"))

  (test-case "struct-lens: should set a field without changing the original struct"
    ;; Given
    (define original (person "Ann" 30))

    ;; When
    (define updated (set-l (struct-lens person name) "Bob" original))

    ;; Then
    (check-equal? updated (person "Bob" 30))
    (check-equal? original (person "Ann" 30))))
