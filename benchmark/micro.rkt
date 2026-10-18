#lang racket/base

(provide
 u1-case u2-case u3-case u4-case u5-case u6-case u7-case u8-case u9-case)

(require
 "case.rkt"
 "handlers.rkt"
 "../main.rkt")

;; All micro-benchmarks use the id effect; this handler answers it.
;; Type: (-> Any (-> Any Any) Any)
(define (id-handler desc k)
  (k (id-effect-value desc)))

;; The plain counterpart of the id handler.
;; Type: (-> Any Any)
(define (id-direct x) x)

;; Type: (-> Natural Natural)
(define (identity-ops n) n)

;; Type: (-> Symbol Symbol (-> Natural (-> Any)) (-> Natural (-> Any)) bench-case)
(define (micro-case id variant monadic plain)
  (bench-case id variant pilot-sizes identity-ops monadic plain equal?))

;; Type: (-> Free Any)
(define (run-id m)
  (run m id-handler))

;; ============================================================
;; U1 chain of n binds of return against let*
;; ============================================================

;; Type: (-> (Listof bench-case))
(define (u1-case)
  (list (micro-case
         'u1 'default
         (lambda (n)
           (lambda ()
             (run-id (for/fold ([m (return 0)]) ([i (in-range n)])
                       (>>= m (lambda (x) (return (add1 x))))))))
         (lambda (n)
           (lambda ()
             (for/fold ([x 0]) ([i (in-range n)])
               (add1 x)))))))

;; ============================================================
;; U2 one perform and run with one handler against one call
;; ============================================================

;; The thunk does n * factor runs.
;; Type: (->* () (Natural) (Listof bench-case))
(define (u2-case [factor 1])
  (list (bench-case
         'u2 'default pilot-sizes (lambda (n) (* n factor))
         (lambda (n)
           (lambda ()
             (for/fold ([sum 0]) ([i (in-range (* n factor))])
               (+ sum (run-id (id 1))))))
         (lambda (n)
           (lambda ()
             (for/fold ([sum 0]) ([i (in-range (* n factor))])
               (+ sum (id-direct 1)))))
         equal?)))

;; ============================================================
;; U3 n perform calls in one do-m block against n direct calls
;; ============================================================

;; Type: (-> Natural Natural Free)
(define (u3-loop-m i n acc)
  (if (= i n)
      (return acc)
      (do-m [v <- (id i)]
            (u3-loop-m (add1 i) n (+ acc v)))))

;; Type: (-> (Listof bench-case))
(define (u3-case)
  (list (micro-case
         'u3 'default
         (lambda (n) (lambda () (run-id (u3-loop-m 0 n 0))))
         (lambda (n)
           (lambda ()
             (for/fold ([acc 0]) ([i (in-range n)])
               (+ acc (id-direct i))))))))

;; ============================================================
;; U4 left-nested and right-nested bind chains
;; ============================================================

;; Type: (-> Natural Natural Free)
(define (u4-right-m i n acc)
  (if (= i n)
      (return acc)
      (>>= (id i) (lambda (x) (u4-right-m (add1 i) n (+ acc x))))))

;; Type: (-> Natural Free)
(define (u4-left-m n)
  (for/fold ([m (id 0)]) ([i (in-range n)])
    (>>= m (lambda (x) (id (add1 x))))))

;; Type: (-> Natural Natural)
(define (u4-left-plain n)
  (for/fold ([x (id-direct 0)]) ([i (in-range n)])
    (id-direct (add1 x))))

;; Type: (-> (Listof bench-case))
(define (u4-case)
  (list (micro-case 'u4 'left
                    (lambda (n) (lambda () (run-id (u4-left-m n))))
                    (lambda (n) (lambda () (u4-left-plain n))))
        (micro-case 'u4 'right
                    (lambda (n) (lambda () (run-id (u4-right-m 0 n 0))))
                    (lambda (n)
                      (lambda ()
                        (for/fold ([acc 0]) ([i (in-range n)])
                          (+ acc (id-direct i))))))))

;; ============================================================
;; U5 recursive effectful procedure, non-tail and tail
;; ============================================================

;; Type: (-> Natural Natural Free)
(define (u5-non-tail-m i n)
  (if (= i n)
      (return 0)
      (do-m [_ <- (id i)]
            [r <- (u5-non-tail-m (add1 i) n)]
            (return (add1 r)))))

;; Type: (-> Natural Natural Natural Free)
(define (u5-tail-m i n acc)
  (if (= i n)
      (return acc)
      (do-m [_ <- (id i)]
            (u5-tail-m (add1 i) n (add1 acc)))))

;; Type: (-> Natural Natural Natural)
(define (u5-non-tail-plain i n)
  (if (= i n)
      0
      (begin (id-direct i)
             (add1 (u5-non-tail-plain (add1 i) n)))))

;; Type: (-> Natural Natural Natural Natural)
(define (u5-tail-plain i n acc)
  (if (= i n)
      acc
      (begin (id-direct i)
             (u5-tail-plain (add1 i) n (add1 acc)))))

;; Type: (-> (Listof bench-case))
(define (u5-case)
  (list (micro-case 'u5 'non-tail
                    (lambda (n) (lambda () (run-id (u5-non-tail-m 0 n))))
                    (lambda (n) (lambda () (u5-non-tail-plain 0 n))))
        (micro-case 'u5 'tail
                    (lambda (n) (lambda () (run-id (u5-tail-m 0 n 0))))
                    (lambda (n) (lambda () (u5-tail-plain 0 n 0))))))

;; ============================================================
;; U6 sequence and map-m against map and for/list
;; ============================================================

;; Type: (-> (Listof bench-case))
(define (u6-case)
  (list (micro-case 'u6 'sequence
                    (lambda (n)
                      (define items (for/list ([i (in-range n)]) i))
                      (lambda () (run-id (sequence (for/list ([i (in-list items)]) (id i))))))
                    (lambda (n)
                      (define items (for/list ([i (in-range n)]) i))
                      (lambda () (for/list ([i (in-list items)]) (id-direct i)))))
        (micro-case 'u6 'map-m
                    (lambda (n)
                      (define items (for/list ([i (in-range n)]) i))
                      (lambda () (run-id (map-m id items))))
                    (lambda (n)
                      (define items (for/list ([i (in-range n)]) i))
                      (lambda () (map id-direct items))))))

;; ============================================================
;; U7 run with k nested handlers against k wrapper procedures
;; ============================================================

;; Type: (-> Natural (-> Any (-> Any Any) Any))
(define (nested-handler k)
  (for/fold ([h id-handler]) ([i (in-range k)])
    (lambda (desc resume) (h desc resume))))

;; Type: (-> Natural (-> Any Any))
(define (nested-wrappers k)
  (for/fold ([f id-direct]) ([i (in-range k)])
    (lambda (x) (f x))))

;; Type: (-> Natural bench-case)
(define (u7-variant k)
  (micro-case 'u7 (string->symbol (format "k~a" k))
              (lambda (n)
                (lambda () (run (u3-loop-m 0 n 0) (nested-handler k))))
              (lambda (n)
                (lambda ()
                  (define call (nested-wrappers k))
                  (for/fold ([acc 0]) ([i (in-range n)])
                    (+ acc (call i)))))))

;; Type: (-> (Listof bench-case))
(define (u7-case)
  (for/list ([k (in-list '(1 2 4 8))])
    (u7-variant k)))

;; ============================================================
;; U8 try and catch against with-handlers and raise
;; ============================================================

(struct no-match ())

;; Type: (-> Natural Free)
(define (u8-descend-m depth)
  (if (zero? depth)
      (try (failure "no match") (return 1))
      (do-m [r <- (u8-descend-m (sub1 depth))]
            (return (add1 r)))))

;; Type: (-> Natural Natural)
(define (u8-descend-plain depth)
  (if (zero? depth)
      (raise (no-match))
      (add1 (u8-descend-plain (sub1 depth)))))

;; Type: (-> Natural Natural Natural Free)
(define (u8-loop-m i n depth acc)
  (if (= i n)
      (return acc)
      (do-m [r <- (catch (if depth
                             (u8-descend-m depth)
                             (try (id i) (return 1))))]
            (u8-loop-m (add1 i) n depth (+ acc r)))))

;; Type: (-> Natural (U Natural #f) Natural)
(define (u8-loop-plain n depth)
  (for/fold ([acc 0]) ([i (in-range n)])
    (+ acc (with-handlers ([no-match? (lambda (e) 1)])
             (if depth
                 (u8-descend-plain depth)
                 (id-direct i))))))

;; Type: (-> Symbol (U Natural #f) bench-case)
(define (u8-variant variant depth)
  (micro-case 'u8 variant
              (lambda (n)
                (lambda ()
                  (run (u8-loop-m 0 n depth 0)
                       (bench-handler '(id failure) #f))))
              (lambda (n)
                (lambda () (u8-loop-plain n depth)))))

;; Type: (-> (Listof bench-case))
(define (u8-case)
  (list (u8-variant 'no-failure #f)
        (u8-variant 'depth-1 1)
        (u8-variant 'depth-8 8)))

;; ============================================================
;; U9 repeated resumption of one waiting computation
;; ============================================================

(define u9-depth 256)

;; A waiting computation with u9-depth binds pending on one effect.
;; Type: (-> Free)
(define (u9-waiting)
  (for/fold ([m (id 0)]) ([i (in-range u9-depth)])
    (>>= m (lambda (x) (return (add1 x))))))

;; Type: (-> Natural Natural)
(define (u9-plain x)
  (for/fold ([acc x]) ([i (in-range u9-depth)])
    (add1 acc)))

;; Type: (-> (Listof bench-case))
(define (u9-case)
  (list (micro-case
         'u9 'default
         (lambda (n)
           (lambda ()
             (run (u9-waiting)
                  (lambda (desc resume)
                    (return (for/fold ([sum 0]) ([i (in-range n)])
                              (+ sum (run (resume i) id-handler))))))))
         (lambda (n)
           (lambda ()
             (for/fold ([sum 0]) ([i (in-range n)])
               (+ sum (u9-plain i))))))))

(module+ test
  (require
   rackunit
   racket/file)

  ;; The case restricted to the given sizes (default: its smallest size).
  (define (cut c [sizes (list (car (bench-case-sizes c)))])
    (struct-copy bench-case c [sizes sizes]))

  (define (variant-of cases variant)
    (for/first ([c (in-list cases)] #:when (eq? (bench-case-variant c) variant)) c))

  (define (run-pair c n)
    (list (((bench-case-monadic c) n)) (((bench-case-plain c) n))))

  (define all-micro-cases
    (list u1-case u2-case u3-case u4-case u5-case u6-case u7-case u8-case u9-case))

  (define data-dir
    (let-values ([(base name dir?) (split-path (variable-reference->module-source (#%variable-reference)))])
      (simplify-path (build-path base 'up "research" "data"))))

  (define (listing dir)
    (if (directory-exists? dir)
        (sort (map path->string (find-files (lambda (_) #t) dir)) string<?)
        '()))

  (test-case "u1-case: should return one case with id 'u1, ops n, and equal results at the smallest size"
    (define cases (u1-case))
    (check-equal? (length cases) 1)
    (check-eq? (bench-case-id (car cases)) 'u1)
    (check-equal? ((bench-case-ops (car cases)) 64) 64)
    (check-equal? (case-check (cut (car cases))) 1))

  (test-case "u1-case: should give equal results when the chain has 1 bind"
    (define c (car (u1-case)))
    (check-equal? (case-check (cut c '(1))) 1)
    (check-equal? (apply equal? (run-pair c 1)) #t))

  (test-case "u2-case: should give equal results at the smallest size and one case"
    (define cases (u2-case))
    (check-equal? (length cases) 1)
    (check-eq? (bench-case-id (car cases)) 'u2)
    (check-equal? (case-check (cut (car cases))) 1))

  (test-case "u2-case: should behave as factor 1 when no factor is given"
    (define default (car (u2-case)))
    (define one (car (u2-case 1)))
    (check-equal? ((bench-case-ops default) 64) ((bench-case-ops one) 64))
    (check-equal? (run-pair default 64) (run-pair one 64)))

  (test-case "u2-case: should scale ops by the batch factor when one is given"
    (define one (car (u2-case 1)))
    (define five (car (u2-case 5)))
    (check-equal? ((bench-case-ops five) 64) (* 5 ((bench-case-ops one) 64)))
    (check-equal? (case-check (cut five)) 1)
    (check-equal? (car (run-pair five 64)) (cadr (run-pair five 64))))

  (test-case "u3-case: should give equal results and ops n at the smallest size"
    (define cases (u3-case))
    (check-equal? ((bench-case-ops (car cases)) 64) 64)
    (check-equal? (case-check (cut (car cases))) 1))

  (test-case "u4-case: should return variants 'left and 'right, each equal at the smallest size"
    (define cases (u4-case))
    (check-equal? (map bench-case-variant cases) '(left right))
    (for ([c (in-list cases)])
      (check-equal? ((bench-case-ops c) 64) 64)
      (check-equal? (case-check (cut c)) 1)))

  (test-case "u5-case: should return variants 'non-tail and 'tail, each equal, and finish at depth 4096"
    (define cases (u5-case))
    (check-equal? (map bench-case-variant cases) '(non-tail tail))
    (for ([c (in-list cases)])
      (check-equal? (case-check (cut c '(4096))) 1)))

  (test-case "u6-case: should return variants 'sequence and 'map-m, each equal at the smallest size and with one element"
    (define cases (u6-case))
    (check-equal? (map bench-case-variant cases) '(sequence map-m))
    (for ([c (in-list cases)])
      (check-equal? (case-check (cut c)) 1)
      (check-equal? (case-check (cut c '(1))) 1)))

  (test-case "u7-case: should return variants for k 1, 2, 4 and 8, each equal"
    (define cases (u7-case))
    (check-equal? (length cases) 4)
    (check-equal? (map bench-case-variant cases) '(k1 k2 k4 k8))
    (for ([c (in-list cases)])
      (check-equal? (case-check (cut c)) 1)))

  (test-case "u8-case: should return a no-failure variant and a failure-at-depth variant, each equal"
    (define cases (u8-case))
    (check-equal? (map bench-case-variant cases) '(no-failure depth-1 depth-8))
    (for ([c (in-list cases)])
      (check-equal? (case-check (cut c)) 1))
    (define failing (variant-of cases 'depth-1))
    (check-equal? (apply equal? (run-pair failing 8)) #t))

  (test-case "u8-case: should catch the failure at depth 1 and at a deeper depth"
    (define cases (u8-case))
    (for ([variant (in-list '(depth-1 depth-8))])
      (define result (run-pair (variant-of cases variant) 4))
      (check-equal? (car result) 4)
      (check-equal? (car result) (cadr result))))

  (test-case "u9-case: should give equal results at the smallest size and one variant"
    (define cases (u9-case))
    (check-equal? (length cases) 1)
    (check-equal? ((bench-case-ops (car cases)) 64) 64)
    (check-equal? (case-check (cut (car cases))) 1))

  (test-case "u1-case to u9-case: should return a non-empty list of bench-cases with the right id, ascending positive sizes, positive ops and thunk builders"
    (for ([make-cases (in-list all-micro-cases)]
          [id (in-list '(u1 u2 u3 u4 u5 u6 u7 u8 u9))])
      (define cases (make-cases))
      (check-true (pair? cases))
      (for ([c (in-list cases)])
        (check-true (bench-case? c))
        (check-eq? (bench-case-id c) id)
        (define sizes (bench-case-sizes c))
        (check-true (andmap exact-positive-integer? sizes))
        (check-equal? sizes (sort sizes <))
        (for ([n (in-list sizes)])
          (check-true (> ((bench-case-ops c) n) 0)))
        (check-true (procedure-arity-includes? ((bench-case-monadic c) 64) 0))
        (check-true (procedure-arity-includes? ((bench-case-plain c) 64) 0)))))

  (test-case "u1-case to u9-case: should do no I/O when only built"
    (define before (listing data-dir))
    (define out (open-output-string))
    (parameterize ([current-output-port out])
      (for ([make-cases (in-list all-micro-cases)])
        (make-cases)))
    (check-equal? (get-output-string out) "")
    (check-equal? (listing data-dir) before)))
