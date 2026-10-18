#lang racket/base

(provide
 (record-out read-state-effect)
 (record-out write-state-effect)
 read-state
 write-state
 update-state
 make-state-store)

(require
 rebellion/type/record
 "../freer-monad.rkt")

(define-record-type read-state-effect (key))
(define-record-type write-state-effect (key value))

;; Type: (-> Any Free)
(define (read-state key)
  (perform (read-state-effect #:key key)))

;; Type: (-> Any Any Free)
(define (write-state key value)
  (perform (write-state-effect #:key key #:value value)))

;; Type: (-> Any (-> Any Any) Free)
(define (update-state key f)
  (>>= (read-state key)
       (lambda (v) (write-state key (f v)))))

;; Type: (->* () ((Listof (Pairof Any Any))) Any)
;; Impure: allocates and mutates a store. Raises exn:fail when the seed repeats a key.
(define (make-state-store [seed '()])
  (define store (make-hasheq))
  (for ([pair (in-list seed)])
    (when (hash-has-key? store (car pair))
      (error 'make-state-store "duplicate key in seed: ~e" (car pair)))
    (hash-set! store (car pair) (cdr pair)))
  store)


(module+ test
  (require
    rackunit
    "../freer-monad.rkt")

  ;; Type: (-> HashEq (-> Any (-> Any Free) Free))
  (define ((state-handler! store) desc k)
    (cond [(read-state-effect? desc) (k (hash-ref store (read-state-effect-key desc)))]
          [(write-state-effect? desc)
           (hash-set! store (write-state-effect-key desc) (write-state-effect-value desc))
           (k (void))]
          [else (error "unexpected effect")]))

  (define (run-state m store) (run m (state-handler! store)))
  (define (store->alist store) (sort (hash->list store) symbol<? #:key car))

  ;; 1
  (test-case "read-state: should build a description of a read without touching the store when built"
    ;; Given
    (define store (make-state-store '((a . 1))))
    ;; When
    (define m (read-state 'a))
    ;; Then
    (check-true (free? m))
    (check-equal? (store->alist store) '((a . 1))))

  ;; 2
  (test-case "write-state: should build a description of a write without touching the store when built"
    ;; Given
    (define store (make-state-store '((a . 1))))
    ;; When
    (define m (write-state 'a 9))
    ;; Then
    (check-true (free? m))
    (check-equal? (store->alist store) '((a . 1))))

  ;; 3
  (test-case "update-state: should not call the function or touch the store when built"
    ;; Given
    (define store (make-state-store '((a . 1))))
    (define called #f)
    (define (f v) (set! called #t) v)
    ;; When
    (define m (update-state 'a f))
    ;; Then
    (check-true (free? m))
    (check-false called)
    (check-equal? (store->alist store) '((a . 1))))

  ;; 4
  (test-case "read-state: should return the starting value when the store held the key at the start"
    ;; Given
    (define store (make-state-store '((a . 1))))
    ;; When
    (define result (run-state (read-state 'a) store))
    ;; Then
    (check-equal? result 1)
    (check-equal? (store->alist store) '((a . 1))))

  ;; 5
  (test-case "write-state: should make a later read return the written value when written then read"
    ;; Given
    (define store (make-state-store '((a . 1))))
    ;; When
    (define result (run-state (>>= (write-state 'a 2) (lambda (_) (read-state 'a))) store))
    ;; Then
    (check-equal? result 2))

  ;; 6
  (test-case "write-state: should make a read return the last value when the key is written twice"
    ;; Given
    (define store (make-state-store '((a . 1))))
    ;; When
    (define result
      (run-state (>>= (write-state 'a 2)
                      (lambda (_) (>>= (write-state 'a 3)
                                       (lambda (_) (read-state 'a)))))
                 store))
    ;; Then
    (check-equal? result 3))

  ;; 7
  (test-case "write-state: should leave the caller's store holding the write when the run ends"
    ;; Given
    (define store (make-state-store))
    ;; When
    (run-state (write-state 'a 5) store)
    ;; Then
    (check-equal? (store->alist store) '((a . 5))))

  ;; 8
  (test-case "update-state: should give the same result and store as read then write when applied"
    ;; Given
    (define s1 (make-state-store '((a . 1) (b . 10))))
    (define s2 (make-state-store '((a . 1) (b . 10))))
    ;; When
    (define r1 (run-state (update-state 'a add1) s1))
    (define r2 (run-state (>>= (read-state 'a) (lambda (v) (write-state 'a (add1 v)))) s2))
    ;; Then
    (check-equal? r1 r2)
    (check-equal? (store->alist s1) '((a . 2) (b . 10)))
    (check-equal? (store->alist s2) '((a . 2) (b . 10))))

  ;; 9
  (test-case "update-state: should leave other keys unchanged when one key is updated"
    ;; Given
    (define store (make-state-store '((a . 1) (b . 10))))
    ;; When
    (run-state (update-state 'a add1) store)
    ;; Then
    (check-equal? (hash-ref store 'b) 10))

  ;; 10
  (test-case "update-state: should raise when the key is missing and the handler raises on a missing key"
    ;; Given
    (define store (make-state-store))
    (define count 0)
    (define (f v) (set! count (add1 count)) v)
    ;; When / Then
    (check-exn exn:fail? (lambda () (run-state (update-state 'a f) store)))
    (check-equal? count 0)
    (check-equal? (hash-count store) 0))

  ;; 11
  (test-case "make-state-store: should hold exactly the seed pairs when given a list of pairs"
    ;; Given
    (define seed '((a . 1) (b . 2)))
    ;; When
    (define store (make-state-store seed))
    ;; Then
    (check-true (hash? store))
    (check-false (immutable? store))
    (check-true (hash-eq? store))
    (check-equal? (store->alist store) '((a . 1) (b . 2))))

  ;; 12
  (test-case "make-state-store: should return an empty store when given no seed"
    ;; When
    (define s1 (make-state-store))
    (define s2 (make-state-store '()))
    ;; Then
    (check-false (immutable? s1))
    (check-false (immutable? s2))
    (check-equal? (hash-count s1) 0)
    (check-equal? (hash-count s2) 0))

  ;; 13
  (test-case "make-state-store: should raise a plain exn:fail naming the key when a key is repeated"
    ;; Given
    (define seed '((dup-key . 1) (b . 2) (dup-key . 3)))
    ;; When
    (define result
      (with-handlers ([exn:fail? values])
        (make-state-store seed)))
    ;; Then
    (check-true (exn:fail? result))
    (check-false (exn:fail:contract? result))
    (check-regexp-match #rx"dup-key" (exn-message result)))

  ;; 15
  (test-case "run-state: should not share writes when the same computation runs on two stores"
    ;; Given
    (define s1 (make-state-store '((a . 0))))
    (define s2 (make-state-store '((a . 0))))
    (define m (write-state 'a 7))
    ;; When
    (run-state m s1)
    ;; Then
    (check-equal? (hash-ref s1 'a) 7)
    (check-equal? (hash-ref s2 'a) 0))

  ;; 16
  (test-case "run-state: should share writes when the same store is used for two runs"
    ;; Given
    (define store (make-state-store '((a . 1))))
    ;; When
    (run-state (update-state 'a add1) store)
    (run-state (update-state 'a add1) store)
    (define result (run-state (read-state 'a) store))
    ;; Then
    (check-equal? result 3))

  ;; 17
  (test-case "make-state-store: should treat equal but non-identical string keys as different keys when compared by eq?"
    ;; Given
    (define k1 (string-copy "k"))
    (define k2 (string-copy "k"))
    (check-true (equal? k1 k2))
    (check-false (eq? k1 k2))
    (define store (make-state-store (list (cons k1 1))))
    ;; When
    (define r1 (run-state (read-state k1) store))
    (define r2 (with-handlers ([exn:fail? (lambda (e) 'raised)])
                 (run-state (read-state k2) store)))
    ;; Then
    (check-equal? r1 1)
    (check-equal? r2 'raised))

  ;; 18
  (test-case "make-state-store: should use one key when the same object is used twice"
    ;; Given
    (define k (string-copy "k"))
    (define store (make-state-store (list (cons k 1))))
    ;; When
    (define result
      (run-state (>>= (write-state k 2) (lambda (_) (read-state k))) store))
    ;; Then
    (check-equal? result 2)
    (check-equal? (hash-count store) 1))

  ;; 19
  (test-case "make-state-store: should not report a duplicate when keys are equal but not identical"
    ;; Given
    (define seed (list (cons (string-copy "k") 1) (cons (string-copy "k") 2)))
    ;; When
    (define store (make-state-store seed))
    ;; Then
    (check-equal? (hash-count store) 2)))
