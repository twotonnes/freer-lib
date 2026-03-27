#lang racket/base

(provide
 (struct-out lens)
 view
 set-l
 set-l*
 over
 lens-compose)

(require
 racket/list)

(struct lens (get set) #:transparent)

(module+ test
  (define left (lens first (lambda (new-value structure)
                             (list-set structure 0 new-value))))
  (define right (lens second (lambda (new-value structure)
                               (list-set structure 1 new-value)))))

(define (view l structure)
  ((lens-get l) structure))
(module+ test
  (require rackunit)
  (test-case "view - extract values correctly"
             (define structure (list 1 2))
             (check-equal? (view left structure) 1)
             (check-equal? (view right structure) 2)))

(define (set-l l new-value structure)
  ((lens-set l) new-value structure))
(module+ test
  (require rackunit)
  (test-case "set - update values correctly"
             (define structure (list 1 2))
             (check-equal? (set-l left 3 structure) '(3 2))
             (check-equal? (set-l right 4 structure) '(1 4)))
  (test-case "set - multiple updates"
             (define structure (list 1 2))
             (check-equal? (set-l right 4 (set-l left 3 structure)) '(3 4))))

(define-syntax set-l* 
  (syntax-rules ()
    [(_ structure) structure]
    [(_ structure [l new-v])
     (set-l l new-v structure)]
    [(_ structure [l new-v] rest ...)
     (set-l* (set-l l new-v structure) rest ...)]))
(module+ test
  (require rackunit)

  (test-case "set* - returns the same structure if no values were provided"
    (define structure (list 1 2))
    (check-equal? (set-l* structure) '(1 2)))

  (test-case "set* - sets single value correctly"
    (define structure (list 1 2))
    (check-equal? (set-l* structure [right 42])
                  '(1 42)))

  (test-case "set* - sets multiple values correctly"
    (define structure (list 1 2))
    (check-equal? (set-l* structure [left 10] [right 20])
                  '(10 20))))

(define (over l update-fn structure)
  (set-l l (update-fn (view l structure)) structure))
(module+ test
  (require rackunit)
  (test-case "over - update values correctly"
             (define structure (list 1 2))
             (check-equal? (over left add1 structure) '(2 2))
             (check-equal? (over right add1 structure) '(1 3))))

(define (compose-lens inner outer)
  (lens (lambda (structure)
          (view inner (view outer structure)))
        (lambda (new-value structure)
          (set-l outer
               (set-l inner new-value (view outer structure))
               structure))))
(module+ test
  (require rackunit)
  (test-case "compose two lenses"
             (define composed-lens
               (compose-lens left right))
             (define structure '((1 2) (3 4)))

             (check-equal? (view composed-lens structure) 3)

             (define updated-structure
               (set-l composed-lens "456 Oak Ave" structure))
             (check-equal? updated-structure '((1 2) ("456 Oak Ave" 4)))))

(define-syntax-rule (lens-compose l1 l2 ...)
  (foldl compose-lens l1 (list l2 ...)))
(module+ test
  (require rackunit)
  (test-case "lens-compose - composing 2 lenses"
             (define composed-lens
               (lens-compose right left right))
             (define structure '((a b) ((1 2) (3 4))))

             (check-equal? (view composed-lens structure) 2)

             (define updated-structure
               (set-l composed-lens "456 Oak Ave" structure))
             (check-equal? updated-structure '((a b) ((1 "456 Oak Ave") (3 4))))))

;; General tests
(module+ test
  (require rackunit)
  ;; Law 1: view (set-l lens value structure) = value
  (test-case "get-set law"
             (define structure (list 1 2))
             (check-equal? (view left
                                 (set-l left "Test" structure))
                           "Test")
             (check-equal? (view right
                                 (set-l right 99 structure))
                           99))
  ;; Law 2: set lens (view lens structure) structure = structure
  (test-case "set-get law"
             (define structure (list 1 2))
             (check-equal? (set-l left
                                (view left structure)
                                structure)
                           structure)
             (check-equal? (set-l right
                                (view right structure)
                                structure)
                           structure))

  ;; Law 3: set lens v2 (set-l lens v1 structure) = set lens v2 structure
  (test-case "set-set law"
             (define structure (list 1 2))
             (check-equal? (set-l left "Final"
                                (set-l left "Intermediate" structure))
                           (set-l left "Final" structure))))
