#lang racket/base

(provide
  effect-desc
  pure
  effect
  return
  run
  >>=
  do
  with-effect-handlers)

(require racket/match
         (for-syntax racket/base))

;; Extensible effect descriptor (currently empty; can hold metadata in subclasses).
(struct effect-desc () #:transparent)

;; `pure` wraps a value; `effect` wraps an effect descriptor and a
;; continuation that will receive the effect's result.
(struct pure (value) #:transparent)
(struct effect (description k) #:transparent)

(define (return v) (pure v))

;; Bind sequences computations while preserving effects: if `m` is
;; `effect`, create a new `effect` with the same description but a
;; continuation that threads the rest of the computation through `f`.
(define (bind m f)
    (match m
        [(pure v) (f v)]
        [(effect desc k)
         (effect desc (lambda (x) (bind (k x) f)))]))

;; Interpreter: run `m` by repeatedly applying `handle` to effects
;; until a `pure` value emerges.
(define (run m handle)
    (match m
        [(pure value) value]
        [(effect desc k) (run (handle (effect desc k)) handle)]))

;; Alias for bind.
(define >>= bind)

;; Do-notation: syntactic sugar for monadic sequencing.
;; All sequences expand to nested `>>=` calls, threading results through.
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
        ;; Useful for effects that matter only for their side effects.
        [(_ m rest ...)
         #'(>>= m (lambda (_) (do rest ...)))]))

;; Macro for pattern-matching effect handlers. Handler clauses with
;; `abort` short-circuit to a pure result; otherwise the body is
;; sequenced and the continuation `k` is invoked via `>>=`.
(define-syntax (with-effect-handlers stx)
    (syntax-case stx (abort)
        [(_ (clause ...) expr ...)
         (with-syntax ([(match-clause ...)
                        (map (lambda (c)
                                (syntax-case c (abort)
                                    ;; Abort: return pure result without invoking `k`.
                                    [(pattern body ... (abort result))
                                     #'[(effect pattern k) body ... (return result)]]
                                    ;; Continue: sequence body and pass result to `k` via `>>=`.
                                    [(pattern body ...)
                                     #'[(effect pattern k) (>>= (begin body ...) k)]]))
                            (syntax->list #'(clause ...)))])
            #'(run (begin expr ...)
                   (lambda (eff)
                     (match eff
                       match-clause ...
                       ;; No handler matched: error with effect description.
                       [_ (error (format "with-effect-handlers: encountered unhandled effect ~a"
                                        (if (effect? eff)
                                            (effect-description eff)
                                            eff)))]))))]))