#lang typed/racket

(provide
  (struct-out id-effect)
  id)

(require "../eff-monad.rkt")

(struct (A) id-effect effect-desc ([info : A]))

(: id (-> Any (Eff Any)))
(define (id v)
    (effect (id-effect v) (lambda (res) (return res))))