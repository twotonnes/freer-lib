#lang racket/base


(provide
  pure
  impure
  return
  perform
  run
  >>=
  do
  with-impure-handlers)


(require racket/match
         (for-syntax racket/base))

(module+ test
  (require rackunit))


;; ============================================================
;; Core Data Structures
;; ============================================================

(struct pure (value) #:transparent)
(struct impure (description k) #:transparent)


;; ============================================================
;; return
;; ============================================================

(define (return v) (pure v))

(module+ test
  (test-case "return creates pure value"
    (check-equal? (return 42) (pure 42))
    (check-equal? (return 'symbol) (pure 'symbol))))


;; ============================================================
;; perform
;; ============================================================

(define (perform desc)
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

(define (bind m f)
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

(define (run m handle)
    (match m
        [(pure value) value]
        [(impure desc k) (run (handle (impure desc k)) handle)]))

(module+ test
  (test-case "run executes pure computation immediately"
    (define result
      (run (return 100)
           (lambda (eff) (error "handler should not be called"))))
    (check-equal? result 100))
  
  (test-case "run invokes handler on impure effects"
    (define result
      (run (perform 'get-value)
           (lambda (eff)
             (match eff
               [(impure 'get-value k) (k 42)]))))
    (check-equal? result 42))
  
  (test-case "run handles multiple effects in sequence"
    (define result
      (run (>>= (perform 'get-x)
                (lambda (x)
                  (>>= (perform 'get-y)
                       (lambda (y) (return (+ x y))))))
           (lambda (eff)
             (match (impure-description eff)
               ['get-x ((impure-k eff) 10)]
               ['get-y ((impure-k eff) 20)]))))
    (check-equal? result 30)))


;; ============================================================
;; do notation
;; ============================================================

(define-syntax (do stx)
    (syntax-case stx (<-)
        ;; Binding case: (do [a <- m] rest ...)
        ;; Expands to (>>= m (lambda (a) (do rest ...)))
        ;; This allows sequencing with named results.
        [(_ [clause <- m] rest ...)
         #'(>>= m
                (lambda (v)
                    (match v [clause (do rest ...)])))]

        ;; Base case: (do m)
        ;; A single expression just returns itself; no sequencing needed.
        [(_ m)
         #'m]
        
        ;; Sequencing case: (do m1 m2 ...)
        ;; Evaluates m1 but discards its result (bound to _), then continues.
        ;; Expands to (>>= m1 (lambda (_) (do m2 ...)))
        [(_ m rest ...)
         #'(>>= m (lambda (_) (do rest ...)))]))

(module+ test
  (test-case "do with single expression returns it"
    (check-equal? (do (return 7)) (pure 7)))
  
  (test-case "do sequences computations with binding"
    (define result
      (do [x <- (return 3)]
          [y <- (return 4)]
          (return (+ x y))))
    (check-equal? result (pure 7)))
  
  (test-case "do sequences without binding (discarding results)"
    (define result
      (do (return 'ignored)
          (return 42)))
    (check-equal? result (pure 42)))
  
  (test-case "do with pattern matching in binding"
    (define result
      (do [(list a b) <- (return (list 10 20))]
          (return (+ a b))))
    (check-equal? result (pure 30)))
  
  (test-case "do with effects"
    (define result
      (run (do [x <- (perform 'get)]
               (return (* x 2)))
           (lambda (eff)
             (match eff
               [(impure 'get k) (k 21)]))))
    (check-equal? result 42)))


;; ============================================================
;; with-impure-handlers
;; ============================================================

;; Macro for pattern-matching handlers for performing request contained in 'impure' nodes.
;; Handler clauses with `abort` short-circuit to a pure result; otherwise the body is
;; sequenced and the continuation `k` is invoked via `>>=`.
(define-syntax (with-impure-handlers stx)
    (syntax-case stx (abort)
        [(_ (clause ...) expr ...)
         (with-syntax ([(match-clause ...)
                        (map (lambda (c)
                                (syntax-case c (abort)
                                    ;; Abort: return pure result without invoking `k`.
                                    [(pattern body ... (abort result))
                                     #'[(impure pattern k) body ... (return result)]]
                                    ;; Continue: sequence body and pass result to `k` via `>>=`.
                                    [(pattern body ...)
                                     #'[(impure pattern k) (>>= (begin body ...) k)]]))
                            (syntax->list #'(clause ...)))])
            #'(run (begin expr ...)
                   (lambda (eff)
                     (match eff
                       match-clause ...
                       ;; No handler matched: error with impure description.
                       [_ (error (format "with-impure-handlers: encountered unhandled impure ~a"
                                        (if (impure? eff)
                                            (impure-description eff)
                                            eff)))]))))]))

(module+ test
  (test-case "with-impure-handlers handles single effect"
    (define result
      (with-impure-handlers
        (['get-name (return "Alice")])
        (perform 'get-name)))
    (check-equal? result "Alice"))
  
  (test-case "with-impure-handlers with continuation"
    (define result
      (with-impure-handlers
        ([x (return (+ x 10))])
        (do [result <- (perform 5)]
            (return (* result 2)))))
    (check-equal? result 30))
  
  (test-case "with-impure-handlers with abort"
    (define result
      (with-impure-handlers
        (['should-abort (abort 'aborted)])
        (do (perform 'should-abort)
            (return 'should-not-reach-here))))
    (check-equal? result 'aborted))
  
  (test-case "with-impure-handlers distinguishes multiple effects"
    (define result
      (with-impure-handlers
        ([(list 'read) (return 100)]
         [(list 'write x) (return (void))])
        (do [val <- (perform (list 'read))]
            (perform (list 'write val))
            (return val))))
    (check-equal? result 100))
  
  (test-case "with-impure-handlers raises error for unhandled effect"
    (check-exn
     #rx"unhandled impure"
     (lambda ()
       (with-impure-handlers
         (['handled-effect (return 'ok)])
         (perform 'unhandled-effect))))))