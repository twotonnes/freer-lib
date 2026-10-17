#lang racket/base

(provide
  (struct-out rnd-effect)
  rnd
  do-rnd)

(require
  "../freer-monad.rkt")

(struct rnd-effect (min max) #:transparent)

;; Type: (-> Integer Integer Free)
(define (rnd min max)
  (perform (rnd-effect min max)))

;; Type: (-> Integer Integer Integer)
(define (do-rnd min max)
  (random min max))


(module+ test
  (require
    rackunit
    "../freer-monad.rkt")

  (test-case "rnd: should perform an rnd-effect with the bounds"
    (check-match (rnd 1 6) (impure (rnd-effect 1 6) _ _)))

  (test-case "do-rnd: should return values within [min, max) for every sample"
    ;; Given
    (random-seed 42)

    ;; When
    (define samples (for/list ([_ (in-range 200)]) (do-rnd 1 4)))

    ;; Then
    (check-true (for/and ([s (in-list samples)]) (and (>= s 1) (< s 4)))))

  (test-case "do-rnd: should raise an error when the range is empty"
    (check-exn exn:fail? (lambda () (do-rnd 5 5)))))
