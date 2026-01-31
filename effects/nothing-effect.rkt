#lang typed/racket

(provide
  (struct-out nothing-effect)
  nothing)

(require
  "../eff-monad.rkt")
  
(struct nothing-effect effect-desc ())

(: nothing (-> (Eff Any)))
(define (nothing)
  (effect (nothing-effect) (inst return Any)))