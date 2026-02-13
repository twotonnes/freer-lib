#lang racket/base

(provide
    try
    catch)

(require
    racket/contract
    racket/match
    racket/bool
    "freer-monad.rkt")

(struct failure-effect (fallback))

(define/contract (try computation fallback)
    (-> free? free? free?)
    (do
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
        (check-equal? result 'success)))

(define/contract (catch computation)
    (-> free? free?)
    (define result (run computation interpreter))
    (if (free? result)
        result
        (return result)))

(define/contract (interpreter eff k)
    (-> any/c (-> any/c free?) free?)
    (match eff
        [(failure-effect fallback) (return fallback)]
        [_ (return (do
                    [value <- (perform eff)]
                    (catch (k value))))]))

(module+ test
    (require
        rackunit
        racket/function
        "effects/id-effect.rkt")

    (define failed-computation
        (return #f))

    (define/contract (test-interpreter kv eff k)
        (-> hash? any/c (-> any/c free?) free?)
        (match eff
            [(id-effect a)
                (hash-set! kv 'id (+ 1 (hash-ref kv 'id 0)))
                (k a)]
            [_ (error (format "the effect handler was called with ~v" eff))]))
    
    (test-case "try/catch: catches failures"
        (define kv (make-hash))
        (define result
            (run (catch
                    (do
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
                    (do
                        [a <- (try (id 1) (return -1))]
                        [b <- (try (id 2) (return -2))]
                        [c <- (try (id 3) (return -3))]
                        (return (+ a b c))))
                 (curry test-interpreter kv)))

        ;; Check that we completed the entire computation.
        (check-equal? result 6)

        ;; Check that no extra interpretations of the id-effects have taken place.
        (check-equal? (hash-ref kv 'id 0) 3)))