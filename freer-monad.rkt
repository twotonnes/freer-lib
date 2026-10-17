#lang racket/base


(provide
  pure
  impure
  free?
  return
  perform
  run
  >>=
  do-m
  sequence
  map-m)


(require racket/match
         racket/list
         (for-syntax racket/base))

(module+ test
  (require rackunit))


;; ============================================================
;; Core Data Structures
;; ============================================================

(struct pure (value) #:transparent)
(struct impure (description k queue) #:transparent)
(struct leaf (f))
(struct node (left right))

;; Type: (-> Any Boolean)
(define (free? m)
  (or (pure? m) (impure? m)))


;; ============================================================
;; return
;; ============================================================

;; Type: (-> Any Pure)
(define (return v)
  (pure v))

(module+ test
  (test-case "return creates pure value"
    (check-equal? (return 42) (pure 42))
    (check-equal? (return 'symbol) (pure 'symbol))))


;; ============================================================
;; perform
;; ============================================================

;; Type: (-> Any Impure)
(define (perform desc)
  (make-impure desc (leaf return)))

;; Type: (-> Any Queue Impure)
(define (make-impure desc queue)
  (impure desc (lambda (x) (resume queue x)) queue))

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

;; Type: (-> Free (-> Any Free) Free)
(define (bind m f)
  (match m
    [(pure v) (f v)]
    [(impure d _ q) (make-impure d (q-append q (leaf f)))]))

;; Type: (-> Queue Any Free)
(define (resume q x)
  (let-values ([(f rest) (q-pop q)])
    (define m (f x))
    (cond [(not rest) m]
          [else (match m
                  [(pure v) (resume rest v)]
                  [(impure d _ q2) (make-impure d (q-append q2 rest))])])))

;; Type: (-> (U Queue #f) (U Queue #f) (U Queue #f))
(define (q-append a b)
  (cond [(not a) b]
        [(not b) a]
        [else (node a b)]))

;; Type: (-> Queue (Values (-> Any Free) (U Queue #f)))
(define (q-pop q)
  (match q
    [(leaf f) (values f #f)]
    [(node (leaf f) r) (values f r)]
    [(node (node a b) r) (q-pop (node a (node b r)))]))

;; Type: (-> Free (-> Any Free) Free)
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

;; Type: (-> Free (-> Any (-> Any Free) Free) Any)
(define (run m handle)
  (match m
    [(pure value) value]
    [(impure desc k _) (run (handle desc k) handle)]))

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

;; ============================================================
;; mapM and sequence implementation
;; ============================================================

;; Type: (-> (Listof Free) [(Listof Any)] Free)
(define (sequence l [acc '()])
  (if (empty? l)
      (return (reverse acc))
      (do-m
        [x <- (first l)]
        (sequence (rest l) (cons x acc)))))
(module+ test
  (require rackunit)
  (test-case "sequence: turns a list of free into a free of list"
    (define l
      (list (return 1) (return 2) (return 3)))
    (define result
      (run (sequence l)
           (lambda (eff k) (error "handler should not be called"))))
    (check-equal? result '(1 2 3))))

;; Type: (-> (-> Any Free) (Listof Any) [(Listof Any)] Free)
(define (map-m proc l [acc '()])
  (if (empty? l)
      (return (reverse acc))
      (do-m
        [x <- (proc (first l))]
        (map-m proc (rest l) (cons x acc)))))
(module+ test
  (require rackunit)
  (test-case "map-m: returns a free of the procedure mapped to the list"
    (define l
      (list 1 2 3))
    (define (proc v)
      (return (* 2 v)))
    (define result
      (run (map-m proc l)
           (lambda (eff k) (error "handler should not be called"))))
    (check-equal? result '(2 4 6))))


;; ============================================================
;; Additional tests: predicates, laws, run, sequence, map-m, do-m
;; ============================================================

(module+ test
  (require rackunit)

  (test-case "free?: should return #t for pure and impure values"
    (check-true (free? (return 1)))
    (check-true (free? (perform 'effect))))

  (test-case "free?: should return #f for values that are not free"
    (check-false (free? 5))
    (check-false (free? 'pure))
    (check-false (free? (list 1 2))))

  (test-case "bind: should satisfy the left identity law"
    ;; Given
    (define f (lambda (x) (return (+ x 1))))

    ;; When
    (define result (>>= (return 3) f))

    ;; Then
    (check-equal? result (f 3)))

  (test-case "bind: should satisfy the right identity law for an impure computation"
    ;; Given
    (define m (perform 'get))
    (define (handle eff k) (k 7))

    ;; When
    (define result (run (>>= m return) handle))

    ;; Then
    (check-equal? result (run m handle)))

  (test-case "bind: should satisfy the associativity law"
    ;; Given
    (define m (return 2))
    (define f (lambda (x) (return (* x 3))))
    (define g (lambda (y) (return (+ y 1))))

    ;; When
    (define left (>>= (>>= m f) g))
    (define right (>>= m (lambda (x) (>>= (f x) g))))

    ;; Then
    (check-equal? left right))

  (test-case "run: should continue with the computation the handler returns"
    ;; Given
    (define computation
      (do-m [x <- (perform 'a)]
            (return x)))

    ;; When
    (define result
      (run computation
           (lambda (eff k)
             (match eff
               ['a (perform 'b)]
               ['b (k 5)]))))

    ;; Then
    (check-equal? result 5))

  (test-case "sequence: should return an empty list when given an empty list"
    (check-equal? (run (sequence '()) (lambda (eff k) (error "handler should not be called")))
                  '()))

  (test-case "sequence: should run effects in order and keep the results in order"
    ;; Given
    (define computation (sequence (list (perform 'a) (return 2) (perform 'b))))

    ;; When
    (define result
      (run computation
           (lambda (eff k)
             (match eff
               ['a (k 1)]
               ['b (k 3)]))))

    ;; Then
    (check-equal? result '(1 2 3)))

  (test-case "map-m: should return an empty list when given an empty list"
    (check-equal? (run (map-m return '()) (lambda (eff k) (error "handler should not be called")))
                  '()))

  (test-case "map-m: should perform an effect for each element and keep the results in order"
    ;; Given
    (define (proc v) (perform v))

    ;; When
    (define result
      (run (map-m proc '(a b))
           (lambda (eff k)
             (match eff
               ['a (k 1)]
               ['b (k 2)]))))

    ;; Then
    (check-equal? result '(1 2)))

  (test-case "do-m: should raise an error when a binding pattern does not match"
    ;; When / Then
    (check-exn exn:fail?
               (lambda ()
                 (run (do-m [(list a b) <- (return 'not-a-list)]
                            (return a))
                      (lambda (eff k) (error "handler should not be called")))))))


;; ============================================================
;; Queue-based bind tests
;; ============================================================

(module+ test
  (require rackunit)

  ;; Returns the functions of a queue in order.
  (define (drain q)
    (let loop ([q q] [acc '()])
      (let-values ([(f rest) (q-pop q)])
        (if rest
            (loop rest (cons f acc))
            (reverse (cons f acc))))))

  ;; Runs m, answering each effect with (answer description k); returns (values result trace).
  (define (traced-run m answer)
    (define trace '())
    (define result
      (run m (lambda (d k)
               (set! trace (cons d trace))
               (answer d k))))
    (values result (reverse trace)))

  (define (no-handler d k) (error "handler should not be called"))
  (define (inc x) (return (+ x 1)))
  (define (times10 x) (return (* x 10)))

  ;; ---- struct impure / pure ----
  (test-case "impure: should match the pattern with three fields when built by perform"
    (check-match (perform 'd) (impure 'd _ (? values))))

  (test-case "impure: should read back its description and fields when built directly with a k and a leaf queue"
    (define k (lambda (x) (return x)))
    (define m (impure 'd k (leaf return)))
    (check-equal? (impure-description m) 'd)
    (match m
      [(impure d k2 q)
       (check-equal? d 'd)
       (check-eq? k2 k)
       (check-pred leaf? q)
       (check-eq? (leaf-f q) return)]))

  (test-case "pure: should equal another pure and match a single field when built with the same value"
    (check-equal? (pure 1) (pure 1))
    (check-match (pure 1) (pure v) (= v 1)))

  ;; ---- free? ----
  (test-case "free?: should return #t when given the result of bind on a waiting computation"
    (check-true (free? (>>= (perform 'a) return))))

  (test-case "free?: should return #f when given #f, '() or a leaf"
    (check-false (free? #f))
    (check-false (free? '()))
    (check-false (free? (leaf return))))

  ;; ---- return ----
  (test-case "return: should hold a free value unchanged when given a free value"
    (check-equal? (return (return 1)) (pure (pure 1))))

  (test-case "return: should hold #f when given #f"
    (check-equal? (return #f) (pure #f)))

  ;; ---- perform ----
  (test-case "perform: should return a waiting computation with the description when given a symbol"
    (define m (perform 'test-effect))
    (check-pred impure? m)
    (check-equal? (impure-description m) 'test-effect))

  (test-case "perform: should hold a single leaf of return as its queue when called"
    (define q (impure-queue (perform 'read)))
    (check-pred leaf? q)
    (check-eq? (leaf-f q) return))

  (test-case "perform: should make k return a pure of its argument when k is applied to 100"
    (check-equal? ((impure-k (perform 'read)) 100) (pure 100)))

  (test-case "perform: should keep the description unchanged when given #f, '() or a struct"
    (check-equal? (impure-description (perform #f)) #f)
    (check-equal? (impure-description (perform '())) '())
    (check-equal? (impure-description (perform (pure 3))) (pure 3)))

  (test-case "perform: should make k return a pure holding a free value when k is applied to a free value"
    (check-equal? ((impure-k (perform 'x)) (return 1)) (pure (pure 1))))

  (test-case "perform: should give independent results when its k is applied to 1 and to 2"
    (define k (impure-k (perform 'x)))
    (check-equal? (k 1) (pure 1))
    (check-equal? (k 2) (pure 2)))

  ;; ---- make-impure ----
  (test-case "make-impure: should build a waiting computation with the given description and queue when given 'd and a leaf"
    (define q (leaf return))
    (define m (make-impure 'd q))
    (check-pred impure? m)
    (check-equal? (impure-description m) 'd)
    (check-eq? (impure-queue m) q)
    (check-true (procedure-arity-includes? (impure-k m) 1)))

  (test-case "make-impure: should make k apply the queue's function to its argument when the queue is a leaf"
    (define m (make-impure 'd (leaf (lambda (x) (return (* 2 x))))))
    (check-equal? ((impure-k m) 4) (pure 8)))

  (test-case "make-impure: should make k apply all pending functions in order when the queue is a node of two leaves"
    (define m (make-impure 'd (node (leaf inc) (leaf times10))))
    (check-equal? ((impure-k m) 1) (pure 20)))

  (test-case "make-impure: should make k return a waiting computation when the pending function performs an effect"
    (define m (make-impure 'd (leaf (lambda (x) (perform (list 'next x))))))
    (define r ((impure-k m) 3))
    (check-pred impure? r)
    (check-equal? (impure-description r) '(next 3)))

  (test-case "make-impure: should give the same result when k is applied twice to the same argument"
    (define m (make-impure 'd (node (leaf inc) (leaf times10))))
    (define k (impure-k m))
    (check-equal? (k 5) (k 5)))

  ;; ---- bind ----
  (test-case "bind: should be the same procedure as >>= when compared with eq?"
    (check-eq? bind >>=))

  (test-case "bind: should return the function's result when m is pure"
    (check-equal? (>>= (return 5) (lambda (x) (return (* x 2)))) (pure 10)))

  (test-case "bind: should return the function's waiting result when m is pure and f performs an effect"
    (define r (>>= (return 5) (lambda (x) (perform (list 'e x)))))
    (check-pred impure? r)
    (check-equal? (impure-description r) '(e 5)))

  (test-case "bind: should pass a free value unchanged to f when m is a pure holding a free value"
    (check-equal? (>>= (return (return 1)) (lambda (x) x)) (pure 1)))

  (test-case "bind: should pass #f to f when m is (pure #f)"
    (check-equal? (>>= (return #f) (lambda (x) (return (list x)))) (pure '(#f))))

  (test-case "bind: should keep the description and append f to the queue when m is waiting"
    (define f inc)
    (define r (>>= (perform 'read-input) f))
    (check-equal? (impure-description r) 'read-input)
    (define q (impure-queue r))
    (check-pred node? q)
    (check-eq? (leaf-f (node-left q)) return)
    (check-eq? (leaf-f (node-right q)) f))

  (test-case "bind: should not call f when m is waiting and has not been resumed"
    (define called #f)
    (>>= (perform 'a) (lambda (x) (set! called #t) (return x)))
    (check-false called))

  (test-case "bind: should call f exactly once with the handler's value when m is waiting and the result is run"
    (define count 0)
    (define result
      (run (>>= (perform 'a) (lambda (x) (set! count (add1 count)) (return (+ x 1))))
           (lambda (d k) (k 41))))
    (check-equal? result 42)
    (check-equal? count 1))

  (test-case "bind: should build a left-nested queue when two binds are applied to a waiting m"
    (define f inc)
    (define g times10)
    (define q (impure-queue (>>= (>>= (perform 'a) f) g)))
    (check-pred node? q)
    (check-pred node? (node-left q))
    (check-eq? (leaf-f (node-left (node-left q))) return)
    (check-eq? (leaf-f (node-right (node-left q))) f)
    (check-eq? (leaf-f (node-right q)) g))

  (test-case "bind: should leave m unchanged when m is waiting and bound"
    (define m (perform 'a))
    (define q (impure-queue m))
    (>>= m inc)
    (check-eq? (impure-queue m) q)
    (check-equal? (run m (lambda (d k) (k 7))) 7))

  (test-case "bind: should apply the functions in bind order when three binds follow one effect"
    (define marks '())
    (define (mark! s) (set! marks (cons s marks)))
    (define r
      (run (>>= (>>= (>>= (perform 'a)
                          (lambda (x) (mark! 'f) (return x)))
                     (lambda (x) (mark! 'g) (return x)))
                (lambda (x) (mark! 'h) (return x)))
           (lambda (d k) (k 1))))
    (check-equal? r 1)
    (check-equal? (reverse marks) '(f g h)))

  (test-case "bind: should raise exn:fail when m is not a free value"
    (check-exn exn:fail? (lambda () (>>= 5 return)))
    (check-exn exn:fail? (lambda () (>>= #f return))))

  (test-case "bind: should return (f 3) when m is (return 3) (left identity)"
    (check-equal? (>>= (return 3) inc) (pure 4)))

  (test-case "bind: should return an equal pure when a pure is bound to return (right identity)"
    (check-equal? (>>= (return 3) return) (pure 3)))

  (test-case "bind: should give the same trace and result as m when a two-effect m is bound to return (right identity)"
    (define m (>>= (perform 'a) (lambda (x) (perform 'b))))
    (define-values (r1 t1) (traced-run m (lambda (d k) (k 1))))
    (define-values (r2 t2) (traced-run (>>= m return) (lambda (d k) (k 1))))
    (check-equal? t1 '(a b))
    (check-equal? t2 '(a b))
    (check-equal? r1 r2))

  (test-case "bind: should give the same trace and result when nested binds on a waiting m are grouped left or right (associativity)"
    (define m (perform 'a))
    (define (f x) (do-m [y <- (perform 'b)] (return (+ x y))))
    (define (g z) (do-m [w <- (perform 'c)] (return (+ z w))))
    (define (answer d k)
      (k (case d [(a) 1] [(b) 2] [(c) 3])))
    (define-values (r1 t1) (traced-run (>>= (>>= m f) g) answer))
    (define-values (r2 t2) (traced-run (>>= m (lambda (x) (>>= (f x) g))) answer))
    (check-equal? t1 '(a b c))
    (check-equal? t2 '(a b c))
    (check-equal? r1 r2))

  (test-case "bind: should give the same trace when m is pure and f and g perform effects, grouped two ways"
    (define (f x) (do-m [y <- (perform 'b)] (return (+ x y))))
    (define (g z) (do-m [w <- (perform 'c)] (return (+ z w))))
    (define (answer d k) (k 1))
    (define-values (r1 t1) (traced-run (>>= (>>= (return 1) f) g) answer))
    (define-values (r2 t2) (traced-run (>>= (return 1) (lambda (x) (>>= (f x) g))) answer))
    (check-equal? t1 '(b c))
    (check-equal? t2 '(b c))
    (check-equal? r1 r2))

  (test-case "bind: should give the same trace and result when four functions are grouped three ways"
    (define m (perform 'a))
    (define ((mk e) x) (do-m [y <- (perform e)] (return (+ x y))))
    (define f1 (mk 'e1))
    (define f2 (mk 'e2))
    (define f3 (mk 'e3))
    (define f4 (mk 'e4))
    (define (answer d k)
      (k (case d [(a) 1] [(e1) 10] [(e2) 20] [(e3) 30] [(e4) 40])))
    (define left (>>= (>>= (>>= (>>= m f1) f2) f3) f4))
    (define right
      (>>= m (lambda (x) (>>= (f1 x) (lambda (y) (>>= (f2 y) (lambda (z) (>>= (f3 z) f4))))))))
    (define mixed
      (>>= (>>= m f1) (lambda (x) (>>= (>>= (f2 x) f3) f4))))
    (define-values (r1 t1) (traced-run left answer))
    (define-values (r2 t2) (traced-run right answer))
    (define-values (r3 t3) (traced-run mixed answer))
    (check-equal? t1 '(a e1 e2 e3 e4))
    (check-equal? t2 t1)
    (check-equal? t3 t1)
    (check-equal? r1 101)
    (check-equal? r2 r1)
    (check-equal? r3 r1))

  ;; ---- q-append ----
  (test-case "q-append: should return #f when both queues are #f"
    (check-false (q-append #f #f)))

  (test-case "q-append: should return the right queue when the left queue is #f"
    (define b (leaf inc))
    (check-eq? (q-append #f b) b))

  (test-case "q-append: should return the left queue when the right queue is #f"
    (define a (leaf inc))
    (check-eq? (q-append a #f) a))

  (test-case "q-append: should return a node with the two queues as children when both are leaves"
    (define a (leaf inc))
    (define b (leaf times10))
    (define q (q-append a b))
    (check-pred node? q)
    (check-eq? (node-left q) a)
    (check-eq? (node-right q) b))

  (test-case "q-append: should not flatten the queues when both are nodes"
    (define a (node (leaf inc) (leaf inc)))
    (define b (node (leaf times10) (leaf times10)))
    (define q (q-append a b))
    (check-eq? (node-left q) a)
    (check-eq? (node-right q) b))

  (test-case "q-append: should leave both input queues unchanged when appending"
    (define fa (list inc times10))
    (define fb (list return inc))
    (define a (node (leaf (car fa)) (leaf (cadr fa))))
    (define b (node (leaf (car fb)) (leaf (cadr fb))))
    (q-append a b)
    (check-equal? (drain a) fa)
    (check-equal? (drain b) fb))

  ;; ---- q-pop ----
  (define (fn i) (lambda (x) (return i)))

  (test-case "q-pop: should return the function and #f when the queue is a leaf"
    (define f (fn 0))
    (define-values (g rest) (q-pop (leaf f)))
    (check-eq? g f)
    (check-false rest))

  (test-case "q-pop: should return the first function and the right child when the queue is a node of two leaves"
    (define a (fn 0))
    (define b (fn 1))
    (define right (leaf b))
    (define-values (f rest) (q-pop (node (leaf a) right)))
    (check-eq? f a)
    (check-eq? rest right))

  (test-case "q-pop: should return the leftmost function and a rotated remainder when the left child is a node"
    (define-values (a b c) (values (fn 0) (fn 1) (fn 2)))
    (define-values (f rest) (q-pop (node (node (leaf a) (leaf b)) (leaf c))))
    (check-eq? f a)
    (check-pred node? rest)
    (check-eq? (leaf-f (node-left rest)) b)
    (check-eq? (leaf-f (node-right rest)) c)
    (check-equal? (drain rest) (list b c)))

  (test-case "q-pop: should rotate repeatedly and keep order when the left spine is three nodes deep"
    (define fs (list (fn 0) (fn 1) (fn 2) (fn 3)))
    (define-values (a b c d) (apply values fs))
    (define q (node (node (node (leaf a) (leaf b)) (leaf c)) (leaf d)))
    (check-equal? (drain q) fs))

  (test-case "q-pop: should return the left leaf's function and the right node unchanged when the right child is a node"
    (define a (fn 0))
    (define rn (node (leaf (fn 1)) (leaf (fn 2))))
    (define-values (f rest) (q-pop (node (leaf a) rn)))
    (check-eq? f a)
    (check-eq? rest rn))

  (test-case "q-pop: should keep left-to-right order when the tree mixes left- and right-nested nodes"
    (define fs (for/list ([i 5]) (fn i)))
    (define-values (a b c d e) (apply values fs))
    (define q (node (node (leaf a) (node (leaf b) (leaf c)))
                    (node (leaf d) (leaf e))))
    (check-equal? (drain q) fs))

  (test-case "q-pop: should keep order when 1000 leaves are left-nested"
    (define fs (for/list ([i 1000]) (fn i)))
    (define q
      (for/fold ([q (leaf (car fs))]) ([f (cdr fs)])
        (node q (leaf f))))
    (check-equal? (drain q) fs))

  (test-case "q-pop: should give the same results when the same queue is popped twice"
    (define fs (list (fn 0) (fn 1) (fn 2)))
    (define q (node (node (leaf (car fs)) (leaf (cadr fs))) (leaf (caddr fs))))
    (check-equal? (drain q) fs)
    (check-equal? (drain q) fs))

  ;; ---- resume ----
  (test-case "resume: should return the function's result when the queue is a single leaf and the result is pure"
    (check-equal? (resume (leaf inc) 1) (pure 2)))

  (test-case "resume: should return the function's waiting result unchanged when the queue is a single leaf and the result is waiting"
    (define m (perform 'x))
    (check-eq? (resume (leaf (lambda (x) m)) 1) m))

  (test-case "resume: should pass a pure result to the next function when the queue has two functions"
    (check-equal? (resume (node (leaf inc) (leaf times10)) 1) (pure 20)))

  (test-case "resume: should apply three functions in order when all results are pure"
    (define q (node (node (leaf inc) (leaf (lambda (x) (return (* x 2)))))
                    (leaf (lambda (x) (return (- x 3))))))
    (check-equal? (resume q 5) (pure 9)))

  (test-case "resume: should stop at the first waiting result and not call later functions when the result is waiting"
    (define called #f)
    (define q (node (leaf (lambda (x) (perform 'b)))
                    (leaf (lambda (x) (set! called #t) (return x)))))
    (define r (resume q 1))
    (check-pred impure? r)
    (check-equal? (impure-description r) 'b)
    (check-false called))

  (test-case "resume: should join the stopped result's queue with the remainder when it stops"
    (define m2 (perform 'b))
    (define rest (leaf return))
    (define r (resume (node (leaf (lambda (x) m2)) rest) 1))
    (check-pred node? (impure-queue r))
    (check-eq? (node-left (impure-queue r)) (impure-queue m2))
    (check-eq? (node-right (impure-queue r)) rest))

  (test-case "resume: should continue with the remainder after the effect when the returned k is applied"
    (define q (node (leaf (lambda (x) (perform 'b)))
                    (leaf (lambda (x) (return (list 'got x))))))
    (define r (resume q 1))
    (check-equal? ((impure-k r) 5) (pure '(got 5))))

  (test-case "resume: should run functions in order when pure, waiting and pure results alternate"
    (define trace '())
    (define (t! s) (set! trace (cons s trace)))
    (define q (node (node (leaf (lambda (x) (t! 'f1) (return x)))
                          (leaf (lambda (x) (t! 'f2) (perform 'e))))
                    (leaf (lambda (x) (t! 'f3) (return x)))))
    (define r (resume q 0))
    (check-equal? (reverse trace) '(f1 f2))
    (check-equal? ((impure-k r) 9) (pure 9))
    (check-equal? (reverse trace) '(f1 f2 f3)))

  (test-case "resume: should keep the remainder's order when the remainder at the stop is a node of two leaves"
    (define trace '())
    (define (t! s) (set! trace (cons s trace)))
    (define q (node (leaf (lambda (x) (perform 'e)))
                    (node (leaf (lambda (x) (t! 'f) (return x)))
                          (node (leaf (lambda (x) (t! 'g) (return x)))
                                (leaf (lambda (x) (t! 'h) (return x)))))))
    (define r (resume q 0))
    (check-equal? ((impure-k r) 1) (pure 1))
    (check-equal? (reverse trace) '(f g h)))

  (test-case "resume: should raise the function's error when a pending function raises"
    (define called #f)
    (define q (node (leaf (lambda (x) (error "boom")))
                    (leaf (lambda (x) (set! called #t) (return x)))))
    (check-exn #rx"boom" (lambda () (resume q 1)))
    (check-false called))

  (test-case "resume: should raise exn:fail when a function that is not last returns a value that is not free"
    (define q (node (leaf (lambda (x) 5)) (leaf return)))
    (check-exn exn:fail? (lambda () (resume q 1))))

  (test-case "resume: should not grow the stack when 100000 left-nested functions return pure"
    (define q
      (for/fold ([q (leaf return)]) ([i 100000])
        (node q (leaf inc))))
    (check-equal? (resume q 0) (pure 100000)))

  (test-case "resume: should not grow the stack when 100000 right-nested functions return pure"
    (define q
      (for/fold ([q (leaf return)]) ([i 100000])
        (node (leaf inc) q)))
    (check-equal? (resume q 0) (pure 100000)))

  (test-case "resume: should give equal results when the same queue is resumed twice with the same value"
    (define fs (list inc times10 inc))
    (define q (node (node (leaf (car fs)) (leaf (cadr fs))) (leaf (caddr fs))))
    (check-equal? (resume q 1) (resume q 1))
    (check-equal? (resume q 1) (pure 21))
    (check-equal? (drain q) fs))

  ;; ---- run ----
  (test-case "run: should pass the description and a one-argument k to the handler when m is waiting"
    (define seen-d #f)
    (define seen-k #f)
    (run (perform 'd) (lambda (d k) (set! seen-d d) (set! seen-k k) (return 0)))
    (check-equal? seen-d 'd)
    (check-true (procedure-arity-includes? seen-k 1)))

  (test-case "run: should return a pure value as the result when m is a pure holding a free value"
    (check-equal? (run (return (return 1)) no-handler) (pure 1)))

  (test-case "run: should return #f when m is (pure #f)"
    (check-false (run (return #f) no-handler)))

  (test-case "run: should return the handler's value without running pending functions when the handler does not call k"
    (define called #f)
    (define r
      (run (>>= (perform 'a) (lambda (x) (set! called #t) (return x)))
           (lambda (d k) (return 'aborted))))
    (check-equal? r 'aborted)
    (check-false called))

  (test-case "run: should call the handler once per effect in effect order when binds are nested to the left"
    (define-values (r t)
      (traced-run (>>= (>>= (perform 'a) (lambda (x) (perform 'b)))
                       (lambda (y) (perform 'c)))
                  (lambda (d k) (k 0))))
    (check-equal? t '(a b c)))

  (test-case "run: should give the same trace and result when the same computation is run twice with the same handler"
    (define m (>>= (perform 'a) (lambda (x) (do-m [y <- (perform 'b)] (return (+ x y))))))
    (define (answer d k) (k 3))
    (define-values (r1 t1) (traced-run m answer))
    (define-values (r2 t2) (traced-run m answer))
    (check-equal? r1 r2)
    (check-equal? t1 t2))

  (test-case "run: should raise exn:fail when m is not a free value"
    (check-exn exn:fail? (lambda () (run 5 no-handler))))

  (test-case "run: should raise exn:fail when the handler returns a value that is not free"
    (check-exn exn:fail? (lambda () (run (perform 'a) (lambda (d k) 5)))))

  ;; ---- error propagation ----
  (define (boom-comp) (>>= (perform 'a) (lambda (x) (error "boom"))))
  (define (good-comp) (>>= (perform 'a) (lambda (x) (return (+ x 1)))))
  (define (k1 d k) (k 1))

  (test-case "run: should raise the continuation's error when a pending function raises"
    (check-exn #rx"boom" (lambda () (run (boom-comp) k1))))

  (test-case "run: should raise the handler's error when the handler raises"
    (check-exn #rx"handler-boom"
               (lambda () (run (perform 'a) (lambda (d k) (error "handler-boom"))))))

  (test-case "run: should return the correct result when a fresh run follows a run that raised in a continuation"
    (check-exn #rx"boom" (lambda () (run (boom-comp) k1)))
    (check-equal? (run (good-comp) k1) 2))

  (test-case "run: should return the correct result when a fresh run follows a run that raised in the handler"
    (check-exn #rx"handler-boom"
               (lambda () (run (perform 'a) (lambda (d k) (error "handler-boom")))))
    (check-equal? (run (good-comp) k1) 2))

  (test-case "run: should give the original result when the same computation is run again after its first run raised in the handler"
    (define m (good-comp))
    (check-exn #rx"handler-boom" (lambda () (run m (lambda (d k) (error "handler-boom")))))
    (check-equal? (run m k1) 2))

  (test-case "run: should propagate a raised non-exn value when a continuation raises a symbol"
    (check-exn (lambda (e) (eq? e 'sym))
               (lambda () (run (>>= (perform 'a) (lambda (x) (raise 'sym))) k1))))

  (test-case "run: should raise the error when the failing function is deep in a left-nested queue of 1000 binds"
    (define (build fail-at)
      (for/fold ([m (perform 'a)]) ([i 1000])
        (>>= m (lambda (x)
                 (if (= i fail-at) (error "boom") (return (+ x 1)))))))
    (check-exn #rx"boom" (lambda () (run (build 500) (lambda (d k) (k 0)))))
    (check-equal? (run (build -1) (lambda (d k) (k 0))) 1000))

  ;; ---- requirement 4 ----
  (test-case "bind: should run to completion when 100000 binds are nested to the left on one effect"
    (define m
      (for/fold ([m (perform 'get)]) ([i 100000])
        (>>= m inc)))
    (check-equal? (run m (lambda (d k) (k 0))) 100000))

  (test-case "bind: should run to completion when 100000 binds are nested to the right with an effect at each level"
    (define ticks 0)
    (define (loop n)
      (if (zero? n)
          (return 0)
          (do-m [_ <- (perform 'tick)]
                [r <- (loop (sub1 n))]
                (return (add1 r)))))
    (define result
      (run (loop 100000) (lambda (d k) (set! ticks (add1 ticks)) (k 0))))
    (check-equal? result 100000)
    (check-equal? ticks 100000))

  (test-case "bind: should run to completion when 100000 binds are nested to the left on a pure computation"
    (define m
      (for/fold ([m (return 0)]) ([i 100000])
        (>>= m inc)))
    (check-equal? (run m no-handler) 100000))

  ;; ---- requirement 7: timing ----
  (test-case "bind: should take a median run time at depth 2n of at most 2.5 times the median at depth n when each level waits for one effect"
    ;; Given
    (define (nested k)
      (if (zero? k)
          (return 0)
          (do-m [x <- (perform 'e)]
                [r <- (nested (sub1 k))]
                (return (+ x r 1)))))
    (define (h d k) (k 0))
    (define n 100000)
    (define (median-ms depth)
      (run (nested depth) h) ; warm-up
      (define times
        (for/list ([i 9])
          (collect-garbage)
          (define start (current-inexact-milliseconds))
          (define result (run (nested depth) h))
          (define elapsed (- (current-inexact-milliseconds) start))
          (check-equal? result depth)
          elapsed))
      (list-ref (sort times <) 4))

    ;; When
    (define median-n (median-ms n))
    (define median-2n (median-ms (* 2 n)))

    ;; Then
    (check-true (<= median-2n (* 2.5 median-n))
                (format "median at n: ~a ms, at 2n: ~a ms" median-n median-2n)))

  ;; ---- requirement 2: resume twice ----
  (define (dup-handler trace-box)
    (define (h d k)
      (set-box! trace-box (cons d (unbox trace-box)))
      (case d
        [(dup) (return (list (run (k 1) h) (run (k 2) h)))]
        [(get) (k 10)]))
    h)

  (test-case "make-impure: should give the recorded results when a handler resumes k twice (R3)"
    (define tb (box '()))
    (define result
      (run (do-m [x <- (perform 'dup)]
                 [y <- (perform 'get)]
                 (return (list x y)))
           (dup-handler tb)))
    (check-equal? result '((1 10) (2 10)))
    (check-equal? (reverse (unbox tb)) '(dup get get)))

  (test-case "resume: should give the recorded results when a handler resumes k twice on left-nested binds with an inner effect (R5)"
    (define tb (box '()))
    (define result
      (run (>>= (>>= (perform 'dup) (lambda (x) (return (+ x 1))))
                (lambda (x) (>>= (perform 'get)
                                 (lambda (y) (return (* 2 (+ x y)))))))
           (dup-handler tb)))
    (check-equal? result '(24 26))
    (check-equal? (reverse (unbox tb)) '(dup get get)))

  (test-case "resume: should give the recorded results when a handler resumes k twice in the middle of map-m (R6)"
    (define tb (box '()))
    (define result (run (map-m perform '(get dup get)) (dup-handler tb)))
    (check-equal? result '((10 1 10) (10 2 10)))
    (check-equal? (reverse (unbox tb)) '(get dup get get)))

  ;; ---- mixed computations ----
  (test-case "run: should give the recorded result and trace when effects, do-m and sequence are mixed (M1)"
    (define-values (r t)
      (traced-run (do-m [a <- (perform 'ask-a)]
                        [xs <- (sequence (list (perform 'ask-b) (return 7) (perform 'ask-c)))]
                        (return (list a xs)))
                  (lambda (d k) (k (case d [(ask-a) 1] [(ask-b) 2] [(ask-c) 3])))))
    (check-equal? r '(1 (2 7 3)))
    (check-equal? t '(ask-a ask-b ask-c)))

  (test-case "run: should give the recorded result and trace when map-m maps an effectful function over a list (M3)"
    (define-values (r t)
      (traced-run (map-m (lambda (n) (do-m [d <- (perform (list 'double n))] (return (+ d 1))))
                         '(1 2 3))
                  (lambda (d k) (k (* 2 (cadr d))))))
    (check-equal? r '(3 5 7))
    (check-equal? t '((double 1) (double 2) (double 3))))

  (test-case "run: should give the recorded result and trace when left-nested binds meet a handler that returns computations (M4)"
    (define-values (r t)
      (traced-run (do-m [x <- (perform 'a)] [y <- (perform 'b)] [z <- (perform 'c)]
                        (return (+ x y z)))
                  (lambda (d k)
                    (case d
                      [(a) (k 1)]
                      [(b) (>>= (perform 'b2) k)]
                      [(b2) (k 10)]
                      [(c) (k 0)]))))
    (check-equal? r 11)
    (check-equal? t '(a b b2 c))))
