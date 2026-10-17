#lang racket/base

(provide
    try
    catch)

(require
    racket/match
    racket/bool
    "freer-monad.rkt")

(struct failure-effect (fallback))

;; Type: (-> Free Free Free)
(define (try computation fallback)
    (do-m
        [value <- computation]
        (if (false? value)
            (perform (failure-effect fallback))
            (return value))))
(module+ test
    (require rackunit)

    (test-case "try: returns failure-effect when computation returns #f"
        (define result
            (run (try (return #f) (return 'fallback))
                 (lambda (eff k)
                    (match eff
                        [(failure-effect fb) fb]
                        [_ (error (format "the effect handler was called with ~v" eff))]))))
        (check-equal? result 'fallback))

    (test-case "try: returns the value when computation returns something else than #f"
        (define result
            (run (try (return 'success) (return 'fallback))
                 (lambda (eff k)
                    (match eff
                        [(failure-effect fb) fb]
                        [_ (error (format "the effect handler was called with ~v" eff))]))))
        (check-equal? result 'success))

    (test-case "try: should return the value when computation returns 0, an empty string, or an empty list"
        ;; Given
        (define no-effects (lambda (eff k) (error "handler should not be called")))

        ;; When / Then
        (check-equal? (run (try (return 0) (return 'fallback)) no-effects) 0)
        (check-equal? (run (try (return "") (return 'fallback)) no-effects) "")
        (check-equal? (run (try (return '()) (return 'fallback)) no-effects) '()))

    (test-case "try: should perform the failure-effect with an effectful fallback when computation returns #f"
        ;; Given
        (define result-of-try (try (return #f) (perform 'fallback-effect)))

        ;; When
        (define result
            (run result-of-try
                 (lambda (eff k)
                    (match eff
                        [(failure-effect fb) (return fb)]
                        [_ (error (format "the effect handler was called with ~v" eff))]))))

        ;; Then
        (check-match result (impure 'fallback-effect _ _))))

;; Type: (-> Free Free)
(define (catch computation)
    (match computation
        [(pure value) (return value)]
        [(impure (failure-effect fallback) _ _) fallback]
        [(impure eff k _) (>>= (perform eff) (lambda (value) (catch (k value))))]))

(module+ test
    (require
        rackunit
        racket/function
        "effects/id-effect.rkt")

    (define failed-computation
        (return #f))

    ;; Type: (-> Hash Any (-> Any Free) Free)
    (define (test-interpreter kv eff k)
        (match eff
            [(id-effect a)
                (hash-set! kv 'id (+ 1 (hash-ref kv 'id 0)))
                (k a)]
            [_ (error (format "the effect handler was called with ~v" eff))]))

    (define (id-handler eff k)
        (match eff
            [(id-effect a) (k a)]
            [_ (error (format "the effect handler was called with ~v" eff))]))

    (test-case "try/catch: catches failures"
        (define kv (make-hash))
        (define result
            (run (catch
                    (do-m
                        [a <- (id 3)]
                        [b <- (try failed-computation (return 'right-fallback))]
                        [c <- (id 5)]
                        (perform 'some-effect)))
                 (curry test-interpreter kv)))

        ;; Check that we got back the fallback.
        (check-equal? result 'right-fallback)

        ;; To verify that the computation actually short-circuited, check whether
        ;; only the first id-effect was interpreted.
        (check-equal? (hash-ref kv 'id 0) 1))

    (test-case "try/catch: does not catch successes"
        (define kv (make-hash))
        (define result
            (run (catch
                    (do-m
                        [a <- (try (id 1) (return -1))]
                        [b <- (try (id 2) (return -2))]
                        [c <- (try (id 3) (return -3))]
                        (return (+ a b c))))
                 (curry test-interpreter kv)))

        ;; Check that we completed the entire computation.
        (check-equal? result 6)

        ;; Check that no extra interpretations of the id-effects have taken place.
        (check-equal? (hash-ref kv 'id 0) 3))

    (test-case "catch: should return a pure computation when the computation has no effects"
        ;; Given
        (define computation (return 5))

        ;; When
        (define result (catch computation))

        ;; Then
        (check-equal? result (return 5)))

    (test-case "catch: should return a pure value unchanged when the value is itself a computation"
        ;; Given
        (define nested (return 1))

        ;; When
        (define result (run (catch (return nested)) (lambda (eff k) (error "handler should not be called"))))

        ;; Then
        (check-equal? result nested))

    (test-case "catch: should forward a non-failure effect to the outer handler and use its result"
        ;; Given
        (define computation
            (do-m [x <- (id 2)]
                  (return (* x 10))))

        ;; When
        (define result (run (catch computation) id-handler))

        ;; Then
        (check-equal? result 20))

    (test-case "catch: should stop at the first failure when two failures occur"
        ;; Given
        (define computation
            (do-m [a <- (try (return #f) (return 'first))]
                  [b <- (try (return #f) (return 'second))]
                  (return (list a b))))

        ;; When
        (define result (run (catch computation) id-handler))

        ;; Then
        (check-equal? result 'first))

    (test-case "catch: should run the effectful fallback when computation fails"
        ;; Given
        (define computation (try (return #f) (id 9)))

        ;; When
        (define result (run (catch computation) id-handler))

        ;; Then
        (check-equal? result 9)))

(module+ test
    (require rackunit)

    (define (traced-run m answer)
        (define trace '())
        (define result
            (run m (lambda (d k)
                      (set! trace (cons d trace))
                      (answer d k))))
        (values result (reverse trace)))

    (test-case "catch: should return the fallback unchanged when the first effect is a failure-effect"
        (define fb (return 'fb))
        (check-eq? (catch (perform (failure-effect fb))) fb))

    (test-case "catch: should discard the pending functions when the failure-effect has pending binds"
        (define c
            (>>= (perform (failure-effect (return 'fb)))
                 (lambda (_) (error "must not run"))))
        (check-equal? (run (catch c) (lambda (d k) (error "handler should not be called"))) 'fb))

    (test-case "catch: should return a waiting computation with the same description when the first effect is not a failure"
        (check-match (catch (perform 'a)) (impure 'a _ _)))

    (test-case "catch: should catch a failure after the effect is resumed when the continuation fails"
        (define c
            (>>= (perform 'a)
                 (lambda (v) (try (return #f) (return 'fb)))))
        (check-equal? (run (catch c) (lambda (d k) (k 7))) 'fb))

    (test-case "catch: should short-circuit at the failure and keep the earlier trace when a failure follows several effects"
        (define c
            (do-m [_ <- (perform 'p)]
                  [_ <- (perform 'q)]
                  [_ <- (try (return #f) (return 'fb))]
                  (perform 'r)))
        (define-values (r t) (traced-run (catch c) (lambda (d k) (k 0))))
        (check-equal? r 'fb)
        (check-equal? t '(p q)))

    (test-case "catch: should catch the failure when three binds are nested to the left on a waiting computation"
        (define f3-called #f)
        (define c
            (>>= (>>= (>>= (perform 'a)
                           (lambda (x) (return x)))
                      (lambda (x) (try (return #f) (return 'fb))))
                 (lambda (x) (set! f3-called #t) (return x))))
        (check-equal? (run (catch c) (lambda (d k) (k 1))) 'fb)
        (check-false f3-called))

    (test-case "catch: should raise exn:fail when the computation is not a free value"
        (check-exn exn:fail? (lambda () (catch 5))))

    (test-case "catch: should raise the continuation's error and leave later runs unaffected when a pending function raises"
        (define (h d k) (k 1))
        (check-exn #rx"boom"
                   (lambda ()
                       (run (catch (>>= (perform 'a) (lambda (x) (error "boom")))) h)))
        (check-equal? (run (catch (>>= (perform 'a) (lambda (x) (return (+ x 1))))) h) 2))

    (test-case "catch: should complete when 1000 effects are nested to the right and none fails"
        (define (loop n)
            (if (zero? n)
                (return 0)
                (do-m [_ <- (perform 'tick)]
                      [r <- (loop (sub1 n))]
                      (return (add1 r)))))
        (check-equal? (run (catch (loop 1000)) (lambda (d k) (k 0))) 1000))

    (test-case "catch: should give the recorded results when a handler resumes a catch computation's k twice (R4)"
        (define trace '())
        (define (h d k)
            (set! trace (cons d trace))
            (match d
                ['dup (return (list (run (k 1) h) (run (k #f) h)))]))
        (define result
            (run (catch (do-m [x <- (perform 'dup)]
                              [y <- (try (return x) (return 'fb))]
                              (return (list x y))))
                 h))
        (check-equal? result '((1 1) fb))
        (check-equal? (reverse trace) '(dup)))

    (test-case "catch: should give the recorded result and trace when an effect precedes a failure with an effectful fallback (M2)"
        (define-values (r t)
            (traced-run (catch (do-m [x <- (perform 'p)]
                                     [y <- (try (return #f) (perform 'fallback-eff))]
                                     (perform 'q)
                                     (return (list x y))))
                        (lambda (d k) (k (case d [(p) 1] [(fallback-eff) 9] [(q) 2])))))
        (check-equal? r 9)
        (check-equal? t '(p fallback-eff)))

    (test-case "catch: should give the recorded result and trace when map-m over a list fails at the second element (M5)"
        (define-values (r t)
            (traced-run (catch (map-m (lambda (n) (try (perform (list 'check n)) (return 'bad)))
                                      '(1 2 3)))
                        (lambda (d k) (k (not (equal? d '(check 2)))))))
        (check-equal? r 'bad)
        (check-equal? t '((check 1) (check 2))))

    (test-case "catch: should give the recorded result and trace when a catch is nested in a catch and a sequence follows (M6)"
        (define-values (r t)
            (traced-run (catch (do-m [x <- (catch (try (return #f) (return 'inner-fb)))]
                                     [y <- (sequence (list (perform 'z) (perform 'z)))]
                                     (return (list x y))))
                        (lambda (d k) (k 5))))
        (check-equal? r '(inner-fb (5 5)))
        (check-equal? t '(z z))))
