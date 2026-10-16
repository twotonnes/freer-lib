#lang racket/base

(provide
  (struct-out id-effect)
  id)

(require
  "../freer-monad.rkt")

(struct id-effect (value) #:transparent)

;; Type: (-> Any Free)
(define (id v)
  (perform (id-effect v)))

(module+ test
  (require rackunit)

  (test-case "id: should perform an id-effect with the value"
    (check-match (id 5) (impure (id-effect 5) _)))

  (test-case "id: should return the value the handler passes back"
    (check-equal? (run (id 5) (lambda (eff k) (k (id-effect-value eff)))) 5)))
