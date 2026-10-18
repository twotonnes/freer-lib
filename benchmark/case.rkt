#lang racket/base

(provide
 (struct-out bench-case)
 (struct-out exn:bench-mismatch)
 pilot-sizes
 case-check)

;; id: Symbol, variant: Symbol, sizes: (Listof Natural),
;; ops: (-> Natural Natural), monadic and plain: (-> Natural (-> Any)),
;; equal?: (-> Any Any Boolean)
(struct bench-case (id variant sizes ops monadic plain equal?))

;; A failed equality check; carries the case id, variant and size.
(struct exn:bench-mismatch exn:fail (id variant n))

;; The pilot size series: 2^6 to 2^17.
;; Type: (Listof Natural)
(define pilot-sizes
  (for/list ([k (in-range 6 18)]) (expt 2 k)))

;; Type: (-> bench-case Natural)
;; Impure: runs the monadic and plain thunks once per size. Raises exn:bench-mismatch at the first size whose results differ.
(define (case-check c)
  (for/fold ([checked 0]) ([n (in-list (bench-case-sizes c))])
    (define monadic-result (((bench-case-monadic c) n)))
    (define plain-result (((bench-case-plain c) n)))
    (unless ((bench-case-equal? c) monadic-result plain-result)
      (raise-mismatch c n))
    (add1 checked)))

;; Type: (-> bench-case Natural Void)
(define (raise-mismatch c n)
  (define id (bench-case-id c))
  (define variant (bench-case-variant c))
  (raise (exn:bench-mismatch
          (format "case-check: monadic and plain results differ for ~a ~a at n=~a" id variant n)
          (current-continuation-marks)
          id variant n)))

(module+ test
  (require rackunit)

  ;; A case whose builders return a thunk giving n (plain gives n + plain-offset).
  (define (fake-case id variant sizes #:plain-offset [offset 0] #:equal [same? equal?])
    (bench-case id variant sizes values
                (lambda (n) (lambda () n))
                (lambda (n) (lambda () (+ n offset)))
                same?))

  ;; ------------------------------------------------------------
  ;; bench-case
  ;; ------------------------------------------------------------

  (test-case "bench-case: should hold the seven fields as given when built"
    ;; Given
    (define (ops n) n)
    (define (monadic n) (lambda () n))
    (define (plain n) (lambda () n))
    ;; When
    (define c (bench-case 'w9 'left '(4 8) ops monadic plain equal?))
    ;; Then
    (check-eq? (bench-case-id c) 'w9)
    (check-eq? (bench-case-variant c) 'left)
    (check-equal? (bench-case-sizes c) '(4 8))
    (check-eq? (bench-case-ops c) ops)
    (check-eq? (bench-case-monadic c) monadic)
    (check-eq? (bench-case-plain c) plain)
    (check-eq? (bench-case-equal? c) equal?))

  (test-case "bench-case: should accept an empty sizes list"
    (check-equal? (bench-case-sizes (fake-case 'w9 'left '())) '()))

  (test-case "bench-case: should not call monadic, plain or equal? when built"
    (define calls 0)
    (define (count . _) (set! calls (add1 calls)) #t)
    (bench-case 'w9 'left '(4) count count count count)
    (check-equal? calls 0))

  ;; ------------------------------------------------------------
  ;; case-check
  ;; ------------------------------------------------------------

  (test-case "case-check: should return the number of sizes when every pair is equal"
    (check-equal? (case-check (fake-case 'w9 'left '(4 8 16))) 3))

  (test-case "case-check: should return 1 when there is one size"
    (check-equal? (case-check (fake-case 'w9 'left '(4))) 1))

  (test-case "case-check: should return 0 and call nothing when sizes is empty"
    ;; Given
    (define calls 0)
    (define (builder n) (set! calls (add1 calls)) (lambda () n))
    (define c (bench-case 'w9 'left '() values builder builder equal?))
    ;; When
    (define result (case-check c))
    ;; Then
    (check-equal? result 0)
    (check-equal? calls 0))

  (test-case "case-check: should raise naming id, variant and n when a pair differs"
    ;; Given
    (define c (fake-case 'w9 'left '(4 8) #:plain-offset 1))
    ;; When
    (define e (with-handlers ([exn:fail? values]) (case-check c)))
    ;; Then
    (check-true (exn:fail? e))
    (check-true (exn:bench-mismatch? e))
    (check-regexp-match #rx"w9" (exn-message e))
    (check-regexp-match #rx"left" (exn-message e))
    (check-regexp-match #rx"4" (exn-message e))
    (check-equal? (exn:bench-mismatch-id e) 'w9)
    (check-equal? (exn:bench-mismatch-variant e) 'left)
    (check-equal? (exn:bench-mismatch-n e) 4))

  (test-case "case-check: should stop at the first mismatch"
    ;; Given
    (define built '())
    (define c
      (bench-case 'w9 'left '(4 8 16) values
                  (lambda (n) (set! built (cons (cons 'm n) built)) (lambda () n))
                  (lambda (n) (set! built (cons (cons 'p n) built))
                    (lambda () (if (>= n 8) (add1 n) n)))
                  equal?))
    ;; When
    (define e (with-handlers ([exn:fail? values]) (case-check c)))
    ;; Then
    (check-true (exn:fail? e))
    (check-equal? (exn:bench-mismatch-n e) 8)
    (check-false (assv 16 (map (lambda (p) (cons (cdr p) (car p))) built))))

  (test-case "case-check: should raise naming the last size when only the last pair differs"
    ;; Given
    (define checked '())
    (define c
      (bench-case 'w9 'left '(4 8 16) values
                  (lambda (n) (lambda () n))
                  (lambda (n) (set! checked (cons n checked))
                    (lambda () (if (= n 16) 0 n)))
                  equal?))
    ;; When
    (define e (with-handlers ([exn:fail? values]) (case-check c)))
    ;; Then
    (check-regexp-match #rx"16" (exn-message e))
    (check-equal? (reverse checked) '(4 8 16)))

  (test-case "case-check: should use the equal? of the case"
    (define (c same?)
      (bench-case 'w9 'left '(4) values
                  (lambda (n) (lambda () 1))
                  (lambda (n) (lambda () 1.0))
                  same?))
    (check-equal? (case-check (c =)) 1)
    (check-exn exn:fail? (lambda () (case-check (c equal?)))))

  (test-case "case-check: should build and run each thunk once per size"
    ;; Given
    (define counts (make-hasheq))
    (define (bump! key) (hash-update! counts key add1 0))
    (define c
      (bench-case 'w9 'left '(4 8 16) values
                  (lambda (n) (bump! 'm-build) (lambda () (bump! 'm-run) n))
                  (lambda (n) (bump! 'p-build) (lambda () (bump! 'p-run) n))
                  equal?))
    ;; When
    (case-check c)
    ;; Then
    (check-equal? (hash-ref counts 'm-build) 3)
    (check-equal? (hash-ref counts 'p-build) 3)
    (check-equal? (hash-ref counts 'm-run) 3)
    (check-equal? (hash-ref counts 'p-run) 3))

  (test-case "case-check: should pass the monadic result first and the plain result second to equal?"
    ;; Given
    (define recorded #f)
    (define c
      (bench-case 'w9 'left '(4) values
                  (lambda (n) (lambda () 'm))
                  (lambda (n) (lambda () 'p))
                  (lambda (a b) (set! recorded (list a b)) #t)))
    ;; When
    (case-check c)
    ;; Then
    (check-equal? recorded '(m p)))

  (test-case "case-check: should raise, not return a count, when the first of several sizes differs"
    (define c
      (bench-case 'w9 'left '(4 8) values
                  (lambda (n) (lambda () n))
                  (lambda (n) (lambda () (if (= n 4) 0 n)))
                  equal?))
    (define result (with-handlers ([exn:fail? (lambda (e) 'raised)]) (case-check c)))
    (check-equal? result 'raised)))
