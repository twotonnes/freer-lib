#lang racket/base

(provide
 bench-handler
 state-handler
 null-log-sink)

(require
 "../effects/env-effect.rkt"
 "../effects/failure-effect.rkt"
 "../effects/id-effect.rkt"
 "../effects/log-effect.rkt"
 "../effects/rnd-effect.rkt"
 "../effects/state-effect.rkt")

;; Discards the log-effect it is given.
;; Type: (-> Any Void)
;; Impure: none beyond the call itself; it writes nothing.
(define (null-log-sink message)
  (void))

;; Handler for the state effect on a store from make-state-store.
;; Type: (-> Any (-> Any (-> Any Any) Any))
;; Impure: reads and writes the store. Raises exn:fail on a missing key or an unknown description.
(define (state-handler store)
  (lambda (desc k)
    (cond [(read-state-effect? desc) (k (state-ref store desc))]
          [(write-state-effect? desc) (state-write! store desc) (k (void))]
          [else (unknown-description 'state-handler desc)])))

;; Type: (-> Any Any Any)
(define (state-ref store desc)
  (define key (read-state-effect-key desc))
  (hash-ref store key (lambda () (error 'state-handler "missing key: ~e" key))))

;; Type: (-> Any Any Void)
(define (state-write! store desc)
  (hash-set! store (write-state-effect-key desc) (write-state-effect-value desc)))

;; Handler for the effects named in effects ('env 'log 'rnd 'failure 'state 'id).
;; config is a hash or association list for env, a store for state, and for rnd a
;; pseudo-random generator, an integer seed, or a hash or alist holding 'seed.
;; Type: (->* ((Listof Symbol) Any) ((-> Any Void)) (-> Any (-> Any Any) Any))
;; Impure: reads the store, writes the store and the sink, advances the generator.
;; Raises exn:fail on a description that is unknown or not enabled.
(define (bench-handler effects config [sink null-log-sink])
  (define (enabled? name) (and (memq name effects) #t))
  (define env? (enabled? 'env))
  (define log? (enabled? 'log))
  (define rnd? (enabled? 'rnd))
  (define failure? (enabled? 'failure))
  (define state? (enabled? 'state))
  (define id? (enabled? 'id))
  (define generator (and rnd? (make-generator config)))
  (lambda (desc k)
    (cond [(and env? (read-env-effect? desc)) (k (config-ref config (read-env-effect-kw desc)))]
          [(and log? (log-effect? desc)) (sink desc) (k (void))]
          [(and rnd? (rnd-effect? desc))
           (k (random (rnd-effect-min desc) (rnd-effect-max desc) generator))]
          [(and failure? (failure-effect? desc)) (k #f)]
          [(and state? (read-state-effect? desc)) (k (state-ref config desc))]
          [(and state? (write-state-effect? desc)) (state-write! config desc) (k (void))]
          [(and id? (id-effect? desc)) (k (id-effect-value desc))]
          [else (unknown-description 'bench-handler desc)])))

;; Type: (-> Any Any Any)
(define (config-ref config key)
  (define (missing) (error 'bench-handler "missing configuration key: ~e" key))
  (cond [(hash? config) (hash-ref config key missing)]
        [(and (list? config) (assq key config)) => cdr]
        [else (missing)]))

;; Type: (-> Any Any)
(define (make-generator config)
  (cond [(pseudo-random-generator? config) config]
        [(exact-positive-integer? config) (seeded-generator config)]
        [else (seeded-generator (config-ref config 'seed))]))

;; Type: (-> Natural Any)
(define (seeded-generator seed)
  (vector->pseudo-random-generator (vector (add1 (modulo seed 4294967000)) 2 3 4 5 6)))

;; Type: (-> Symbol Any Void)
(define (unknown-description who desc)
  (error who "unknown description: ~e" desc))

(module+ test
  (require
   rackunit
   "../freer-monad.rkt"
   "../try-catch.rkt")

  (struct mystery ())

  ;; A sink that stores the messages it receives, newest first.
  (define (counting-sink)
    (define messages '())
    (values (lambda (m) (set! messages (cons m messages)))
            (lambda () messages)))

  (define (store->alist store) (sort (hash->list store) symbol<? #:key car))

  ;; ------------------------------------------------------------
  ;; bench-handler
  ;; ------------------------------------------------------------

  (test-case "bench-handler: should answer read-env with the configured value"
    (define h (bench-handler '(env) (hasheq 'limit 10)))
    (check-equal? (run (read-env 'limit) h) 10))

  (test-case "bench-handler: should send log messages to the sink"
    ;; Given
    (define-values (sink messages) (counting-sink))
    (define h (bench-handler '(log) #f sink))
    ;; When
    (run (log-inf "hello") h)
    ;; Then
    (check-equal? (length (messages)) 1)
    (check-equal? (car (messages)) (log-effect 'INFO "hello")))

  (test-case "bench-handler: should answer rnd from a seeded generator"
    ;; Given
    (define (draws)
      (run (do-m [a <- (rnd 0 1000000)] [b <- (rnd 0 1000000)] (return (list a b)))
           (bench-handler '(rnd) 42)))
    ;; When
    (define first-run (draws))
    (define second-run (draws))
    ;; Then
    (check-equal? first-run second-run)
    (check-equal? (length first-run) 2))

  (test-case "bench-handler: should produce the library failure when a failure description is performed"
    ;; Given
    (define continued? #f)
    (define m
      (catch (do-m [v <- (try (failure "boom") (return 'caught))]
                   (set! continued? #t)
                   (return 'normal))))
    ;; When
    (define result (run m (bench-handler '(failure) #f)))
    ;; Then
    (check-equal? result 'caught)
    (check-false continued?))

  (test-case "bench-handler: should read and write the store when effects include state"
    ;; Given
    (define store (make-state-store '((a . 1))))
    (define h (bench-handler '(state) store))
    ;; When
    (define read-value
      (run (do-m [v <- (read-state 'a)] (write-state 'a 5) (return v)) h))
    ;; Then
    (check-equal? read-value 1)
    (check-equal? (store->alist store) '((a . 5))))

  (test-case "bench-handler: should raise naming the description when it is not in the effect list"
    (define h (bench-handler '(env) (hasheq)))
    (define e (with-handlers ([exn:fail? values]) (run (log-inf "x") h)))
    (check-true (exn:fail? e))
    (check-regexp-match #rx"log-effect" (exn-message e)))

  (test-case "bench-handler: should raise naming the description when the description is unknown"
    (define h (bench-handler '(env log failure state id) (make-state-store)))
    (define e (with-handlers ([exn:fail? values]) (run (perform (mystery)) h)))
    (check-true (exn:fail? e))
    (check-regexp-match #rx"mystery" (exn-message e)))

  (test-case "bench-handler: should not let try catch an unknown description"
    (define h (bench-handler '(env) (hasheq)))
    (define m (catch (try (perform (mystery)) (return 'caught))))
    (define e (with-handlers ([exn:fail? values]) (run m h)))
    (check-true (exn:fail? e))
    (check-regexp-match #rx"mystery" (exn-message e)))

  (test-case "bench-handler: should discard log messages when no sink is given"
    ;; Given
    (define h (bench-handler '(log) #f))
    (define out (open-output-string))
    ;; When
    (parameterize ([current-output-port out] [current-error-port out])
      (run (log-inf "hello") h))
    ;; Then
    (check-equal? (get-output-string out) ""))

  (test-case "bench-handler: should return a procedure of two arguments"
    (check-true (procedure-arity-includes? (bench-handler '(env) (hasheq)) 2)))

  (test-case "bench-handler: should raise on any description when the effect list is empty"
    (define h (bench-handler '() #f))
    (check-exn exn:fail? (lambda () (run (read-env 'limit) h)))
    (check-exn exn:fail? (lambda () (run (log-inf "x") h))))

  ;; ------------------------------------------------------------
  ;; state-handler
  ;; ------------------------------------------------------------

  (test-case "state-handler: should answer read-state with the stored value"
    (define store (make-state-store '((a . 1))))
    (check-equal? (run (read-state 'a) (state-handler store)) 1))

  (test-case "state-handler: should make a later read return a written value"
    (define store (make-state-store '((a . 1))))
    (define result
      (run (do-m (write-state 'a 2) (read-state 'a)) (state-handler store)))
    (check-equal? result 2)
    (check-equal? (store->alist store) '((a . 2))))

  (test-case "state-handler: should raise when the key is missing"
    (define store (make-state-store))
    (check-exn exn:fail? (lambda () (run (read-state 'a) (state-handler store)))))

  (test-case "state-handler: should raise naming an unknown description and not be caught by try"
    (define m (catch (try (perform (mystery)) (return 'caught))))
    (define e (with-handlers ([exn:fail? values])
                (run m (state-handler (make-state-store)))))
    (check-true (exn:fail? e))
    (check-regexp-match #rx"mystery" (exn-message e)))

  (test-case "state-handler: should behave as the state-effect test handler for update-state"
    ;; Given
    (define (reference-handler store)
      (lambda (desc k)
        (cond [(read-state-effect? desc) (k (hash-ref store (read-state-effect-key desc)))]
              [(write-state-effect? desc)
               (hash-set! store (write-state-effect-key desc) (write-state-effect-value desc))
               (k (void))]
              [else (error "unexpected effect")])))
    (define mine (make-state-store '((a . 1) (b . 10))))
    (define reference (make-state-store '((a . 1) (b . 10))))
    ;; When
    (define r1 (run (update-state 'a add1) (state-handler mine)))
    (define r2 (run (update-state 'a add1) (reference-handler reference)))
    ;; Then
    (check-equal? r1 r2)
    (check-equal? (store->alist mine) (store->alist reference))
    (check-equal? (store->alist mine) '((a . 2) (b . 10))))

  ;; ------------------------------------------------------------
  ;; null-log-sink
  ;; ------------------------------------------------------------

  (test-case "null-log-sink: should write nothing and return when given a message"
    (define out (open-output-string))
    (define err (open-output-string))
    (parameterize ([current-output-port out] [current-error-port err])
      (null-log-sink "x"))
    (check-equal? (get-output-string out) "")
    (check-equal? (get-output-string err) ""))

  (test-case "null-log-sink: should accept any value"
    (for ([v (in-list (list "" #f 'sym '(1 2)))])
      (check-not-exn (lambda () (null-log-sink v))))))
