#lang racket/base


(provide
  pure
  impure
  free?
  return
  perform
  run
  >>=
  do-m)


(require racket/match
         racket/contract
         (for-syntax racket/base))

(module+ test
  (require rackunit))


;; ============================================================
;; Core Data Structures
;; ============================================================

(struct pure (value) #:transparent)
(struct impure (description k) #:transparent)

(define (free? m)
  (or (pure? m) (impure? m)))


;; ============================================================
;; return
;; ============================================================

(define/contract (return v)
  (-> any/c pure?)
  (pure v))

(module+ test
  (test-case "return creates pure value"
    (check-equal? (return 42) (pure 42))
    (check-equal? (return 'symbol) (pure 'symbol))))


;; ============================================================
;; perform
;; ============================================================

(define/contract (perform desc)
  (-> any/c impure?)
  (impure desc return))

(module+ test
  (test-case "perform creates impure effect"
    (define eff (perform 'test-effect))
    (check-pred impure? eff)
    (check-equal? (impure-description eff) 'test-effect))
  
  (test-case "perform wraps continuation with return"
    (define eff (perform 'read))
    (check-equal? ((impure-k eff) 100) (pure 100))))


;; ============================================================
;; bind (>>=)
;; ============================================================

(define/contract (bind m f)
  (-> free? (-> any/c free?) free?)
  (match m
      [(pure v) (f v)]
      [(impure desc k)
        (impure desc (lambda (x) (bind (k x) f)))]))

(define >>= bind)

(module+ test
  (test-case "bind with pure values sequences correctly"
    (define result
      (>>= (return 5)
           (lambda (x) (return (* x 2)))))
    (check-equal? result (pure 10)))
  
  (test-case "bind accumulates continuations in impure"
    (define result
      (>>= (perform 'read-input)
           (lambda (x) (return (+ x 1)))))
    (check-pred impure? result)
    (check-equal? (impure-description result) 'read-input))
  
  (test-case "multiple binds chain continuations"
    (define result
      (>>= (>>= (return 2)
                (lambda (x) (return (* x 3))))
           (lambda (y) (return (+ y 10)))))
    (check-equal? result (pure 16))))


;; ============================================================
;; run
;; ============================================================

(define/contract (run m handle)
  (-> free? (-> any/c (-> any/c free?) free?) any/c)
  (match m
      [(pure value) value]
      [(impure desc k) (run (handle desc k) handle)]))

(module+ test
  (test-case "run executes pure computation immediately"
    (define result
      (run (return 100)
           (lambda (eff k) (error "handler should not be called"))))
    (check-equal? result 100))
  
  (test-case "run invokes handler on impure effects"
    (define result
      (run (perform 'get-value)
           (lambda (eff k)
             (match eff
               ['get-value (k 42)]))))
    (check-equal? result 42))
  
  (test-case "run handles multiple effects in sequence"
    (define result
      (run (>>= (perform 'get-x)
                (lambda (x)
                  (>>= (perform 'get-y)
                       (lambda (y) (return (+ x y))))))
           (lambda (eff k)
             (match eff
               ['get-x (k 10)]
               ['get-y (k 20)]))))
    (check-equal? result 30)))


;; ============================================================
;; do notation
;; ============================================================

(define-syntax (do-m stx)
    (syntax-case stx (<-)
        ;; Binding case: (do-m [a <- m] rest ...)
        ;; Expands to (>>= m (lambda (a) (do-m rest ...)))
        ;; This allows sequencing with named results.
        [(_ [clause <- m] rest ...)
         #'(>>= m
                (lambda (v)
                    (match v [clause (do-m rest ...)])))]

        ;; Base case: (do-m m)
        ;; A single expression just returns itself; no sequencing needed.
        [(_ m)
         #'m]
        
        ;; Sequencing case: (do-m m1 m2 ...)
        ;; Evaluates m1 but discards its result (bound to _), then continues.
        ;; Expands to (>>= m1 (lambda (_) (do-m m2 ...)))
        [(_ m rest ...)
         #'(>>= m (lambda (_) (do-m rest ...)))]))

(module+ test
  (test-case "do with single expression returns it"
    (check-equal? (do-m (return 7)) (pure 7)))
  
  (test-case "do sequences computations with binding"
    (define result
      (do-m [x <- (return 3)]
          [y <- (return 4)]
          (return (+ x y))))
    (check-equal? result (pure 7)))
  
  (test-case "do sequences without binding (discarding results)"
    (define result
      (do-m (return 'ignored)
          (return 42)))
    (check-equal? result (pure 42)))
  
  (test-case "do with pattern matching in binding"
    (define result
      (do-m [(list a b) <- (return (list 10 20))]
          (return (+ a b))))
    (check-equal? result (pure 30)))
  
  (test-case "do with effects"
    (define result
      (run (do-m [x <- (perform 'get)]
               (return (* x 2)))
           (lambda (eff k)
             (match eff
               ['get (k 21)]))))
    (check-equal? result 42)))
