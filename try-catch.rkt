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
        (check-match result (impure 'fallback-effect _))))

;; Type: (-> Free Free)
(define (catch computation)
    (match computation
        [(pure value) (return value)]
        [(impure (failure-effect fallback) _) fallback]
        [(impure eff k) (impure eff (lambda (value) (catch (k value))))]))

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
