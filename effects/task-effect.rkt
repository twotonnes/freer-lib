#lang racket/base

(provide
 (record-out spawn-effect)
 (record-out await-effect)
 (record-out poll-effect)
 (struct-out task-success)
 (struct-out task-failure)
 (struct-out task-running)
 spawn
 await
 poll
 map-par
 run-par
 collect-par)

(require
 rebellion/type/record
 racket/match
 "../freer-monad.rkt"
 "../try-catch.rkt")

;; Type: (define-record-type spawn-effect (computation))
(define-record-type spawn-effect (computation))
;; Type: (define-record-type await-effect (handle))
(define-record-type await-effect (handle))
;; Type: (define-record-type poll-effect (handle))
(define-record-type poll-effect (handle))

;; Type: (struct task-success (value) #:transparent)
(struct task-success (value) #:transparent)
;; Type: (struct task-failure (value) #:transparent)
(struct task-failure (value) #:transparent)
;; Type: (struct task-running () #:transparent)
(struct task-running () #:transparent)

;; Type: (-> Free Free)
(define (spawn computation)
  (perform (spawn-effect #:computation computation)))

;; Type: (-> Any Free)
(define (await handle)
  (perform (await-effect #:handle handle)))

;; Type: (-> Any Free)
(define (poll handle)
  (perform (poll-effect #:handle handle)))

;; Type: (-> (-> Any Free) (Listof Any) Free)
(define (map-par f xs)
  (do-m [hs <- (map-m (lambda (x) (spawn (f x))) xs)]
        [os <- (map-m await hs)]
        (return os)))

;; Type: (-> (Listof Free) Free)
(define (run-par ms)
  (do-m [hs <- (map-m spawn ms)]
        [os <- (map-m await hs)]
        (return os)))

;; Type: (-> (Listof (U task-success task-failure)) Free)
(define (collect-par outcomes)
  (let loop ([os outcomes] [acc '()])
    (match os
      ['() (return (reverse acc))]
      [(cons (task-success value) rest)
       (loop rest (cons value acc))]
      [(cons (and outcome (task-failure _)) _)
       (perform (try-failure-effect (return (task-failure-value outcome))))]
      [(cons outcome _)
       (error 'collect-par "not a task outcome: ~e" outcome)])))


(module+ test
  (require
    rackunit
    racket/match
    "../freer-monad.rkt")

  ;; Type: (-> Box (-> Any (-> Any Free) Free))
  ;; Test handler that counts the descriptions it answers.
  (define ((counting-handler! box) desc k)
    (set-box! box (add1 (unbox box)))
    (k 'answered))

  ;; 1
  (test-case "spawn: should build a waiting computation when given a computation"
    ;; Given
    (define m (return 5))
    ;; When
    (define result (spawn m))
    ;; Then
    (check-true (free? result))
    (check-match result (impure (spawn-effect #:computation (== m)) _ _)))

  ;; 2
  (test-case "await: should build a waiting computation when given a handle"
    ;; Given
    (define handle 'some-handle)
    ;; When
    (define result (await handle))
    ;; Then
    (check-true (free? result))
    (check-match result (impure (await-effect #:handle (== handle)) _ _)))

  ;; 3
  (test-case "poll: should build a waiting computation when given a handle"
    ;; Given
    (define handle 'some-handle)
    ;; When
    (define result (poll handle))
    ;; Then
    (check-true (free? result))
    (check-match result (impure (poll-effect #:handle (== handle)) _ _)))

  ;; 4
  (test-case "map-par: should build a computation that starts with a spawn when given a non-empty list"
    ;; Given
    (define (f x) (return (* x 2)))
    ;; When
    (define result (map-par f '(1 2 3)))
    ;; Then
    (check-true (free? result))
    (check-match result (impure (spawn-effect #:computation (== (pure 2))) _ _)))

  ;; 5
  (test-case "run-par: should build a computation that starts with a spawn when given a non-empty list"
    ;; Given
    (define ms (list (return 1) (return 2)))
    ;; When
    (define result (run-par ms))
    ;; Then
    (check-true (free? result))
    (check-match result (impure (spawn-effect #:computation (== (pure 1))) _ _)))

  ;; 6
  (test-case "map-par: should answer the empty list purely when given no elements"
    ;; Given / When
    (define result (map-par (lambda (x) (return x)) '()))
    ;; Then
    (check-equal? result (pure '())))

  ;; 7
  (test-case "run-par: should answer the empty list purely when given no elements"
    ;; Given / When
    (define result (run-par '()))
    ;; Then
    (check-equal? result (pure '())))

  ;; 8
  (test-case "collect-par: should answer the values without performing any effect when all outcomes succeed"
    ;; Given
    (define count (box 0))
    (define outcomes (list (task-success 1) (task-success 2) (task-success 3)))
    ;; When
    (define result (run (collect-par outcomes) (counting-handler! count)))
    ;; Then
    (check-equal? result '(1 2 3))
    (check-equal? (unbox count) 0))

  ;; 9
  (test-case "collect-par: should perform the parent failure when an outcome fails"
    ;; Given
    (define outcomes (list (task-success 1) (task-failure 'bad)))
    ;; When
    (define result (collect-par outcomes))
    ;; Then
    (check-match result (impure (try-failure-effect (== (pure 'bad))) _ _)))

  ;; 10
  (test-case "collect-par: should raise a plain exn:fail when given a non-outcome"
    ;; Given
    (define outcomes (list (task-success 1) 'not-an-outcome))
    ;; When
    (define result
      (with-handlers ([exn:fail? values])
        (collect-par outcomes)))
    ;; Then
    (check-true (exn:fail? result))
    (check-false (exn:fail:contract? result))))
