#lang typed/racket

(provide
  effect-desc
  pure
  effect
  Eff
  return
  run
  >>=
  do
  with-effect-handlers)

;; Extensible effect descriptor (currently empty; can hold metadata in subclasses).
(struct effect-desc () #:transparent)

;; `pure` wraps a value; `effect` wraps an effect descriptor and a
;; continuation that will receive the effect's result.
(struct (A) pure ([value : A]) #:transparent)
(struct (A) effect ([description : effect-desc]
                    [k : (-> Any (Eff A))]) #:transparent)

;; The Eff type is a simple union: either a pure value or an effect.
(define-type (Eff A) (U (pure A) (effect A)))

;; Lift a value into Eff via `pure`.
(: return (All (A) (-> A (Eff A))))
(define (return v) (pure v))

;; Bind sequences computations while preserving effects: if `m` is
;; `effect`, create a new `effect` with the same description but a
;; continuation that threads the rest of the computation through `f`.
(: bind (All (A B) (-> (Eff A) (-> A (Eff B)) (Eff B))))
(define (bind m f)
    (match m
        [(pure v) (f v)]
        [(effect desc k)
         (effect desc (lambda (x) (bind (k x) f)))]))

;; Interpreter: run `m` by repeatedly applying `handle` to effects
;; until a `pure` value emerges.
(: run (-> (Eff Any) (-> (effect Any) (Eff Any)) Any))
(define (run m handle)
    (match m
        [(pure value) value]
        [(effect desc k) (run (handle (effect desc k)) handle)]))

;; Alias for bind.
(: >>= (All (A B) (-> (Eff A) (-> A (Eff B)) (Eff B))))
(define (>>= m f) (bind m f))

;; Do-notation: syntactic sugar for monadic sequencing.
;; All sequences expand to nested `>>=` calls, threading results through.
(define-syntax (do stx)
    (syntax-case stx (<-)
        ;; Binding case: (do [a <- m] rest ...)
        ;; Expands to (>>= m (lambda (a) (do rest ...)))
        ;; This allows sequencing with named results.
        [(_ [a <- m] rest ...)
         #'(>>= m (lambda (a) (do rest ...)))]

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
                   (lambda #:forall (A) ([eff : (Eff A)])
                     (match eff
                       match-clause ...
                       ;; No handler matched: error with effect description.
                       [_ (error (format "with-effect-handlers: encountered unhandled effect ~a"
                                        (if (effect? eff)
                                            (effect-description eff)
                                            eff)))]))))]))