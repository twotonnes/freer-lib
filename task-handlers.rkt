#lang racket/base

(provide
    task-handle?
    make-parallel-task-handler
    make-sequential-task-handler
    make-locked-handler)

(require
    racket/match
    "freer-monad.rkt"
    "try-catch.rkt"
    "effects/task-effect.rkt")

;; Type: (struct task-handle (computation base [thread #:mutable] [outcome #:mutable] [done? #:mutable]))
(struct task-handle (computation base
                     [thread #:mutable]
                     [outcome #:mutable]
                     [done? #:mutable]))

;; Resumes with the handle's recorded outcome, re-raising a recorded raise.
;; Type: (-> task-handle (-> Any Free) Free)
(define (deliver-outcome handle k)
    (define o (task-handle-outcome handle))
    (if (or (task-success? o) (task-failure? o))
        (k o)
        (raise o)))

;; Runs a task computation to its outcome: its value wrapped in a task-success,
;; or the task-failure the body's failure clause built.
;; Type: (-> Free (-> Any (-> Any Free) Free) (U task-success task-failure))
(define (run-to-outcome computation body-handler)
    (run (>>= computation (lambda (v) (return (task-success v))))
        body-handler))

;; Given the parent-facing task handler, answers the maker of the handler each
;; task body runs under: a failure is caught at the task boundary, task effects
;; are dispatched like the parent's handler, everything else goes to the task's
;; base.
;; Type: (-> (-> Any (-> Any Free) Free) (-> (-> Any (-> Any Free) Free) (-> Any (-> Any Free) Free)))
(define (make-body h)
    (lambda (task-base)
        (lambda (desc k)
            (cond
                [(try-failure-effect? desc)
                 (>>= (catch (try-failure-effect-fallback desc))
                     (lambda (v) (return (task-failure v))))]
                [(or (spawn-effect? desc) (await-effect? desc) (poll-effect? desc))
                 (h desc k)]
                [else (task-base desc k)]))))

;; The answered handler starts a Racket thread per spawned task and waits on
;; that thread at each await.
;; Type: (-> (-> Any (-> Any Free) Free) [#:fresh (-> (-> Any (-> Any Free) Free)] (-> Any (-> Any Free) Free))
;; Impure: starts a Racket thread per spawned task; waits on that thread at each await.
(define (make-parallel-task-handler base #:fresh [fresh #f])
    ;; Type: (-> Any (-> Any Free) Free)
    (define (h desc k)
        (cond
            [(spawn-effect? desc)
             (define task-base (if fresh (fresh) base))
             (define handle
                 (task-handle (spawn-effect-computation desc) task-base #f #f #f))
             (define t
                 (thread
                     (lambda ()
                         (set-task-handle-outcome!
                          handle
                          (with-handlers ([values (lambda (e) e)])
                              (run-to-outcome (task-handle-computation handle)
                                  (body task-base)))))))
             (set-task-handle-thread! handle t)
             (k handle)]
            [(await-effect? desc)
             (define handle (await-effect-handle desc))
             (thread-wait (task-handle-thread handle))
             (deliver-outcome handle k)]
            [(poll-effect? desc)
             (define handle (poll-effect-handle desc))
             (if (thread-dead? (task-handle-thread handle))
                 (deliver-outcome handle k)
                 (k (task-running)))]
            [else (base desc k)]))

    ;; Type: (-> (-> Any (-> Any Free) Free) (-> Any (-> Any Free) Free))
    (define body (make-body h))
    h)

;; The answered handler runs each spawned task inline at its first await, on
;; the caller's thread.
;; Type: (-> (-> Any (-> Any Free) Free) [#:fresh (-> (-> Any (-> Any Free) Free)] (-> Any (-> Any Free) Free))
;; Impure: runs each spawned task inline at its first await, on the caller's thread.
(define (make-sequential-task-handler base #:fresh [fresh #f])
    ;; Type: (-> Any (-> Any Free) Free)
    (define (h desc k)
        (cond
            [(spawn-effect? desc)
             (define task-base (if fresh (fresh) base))
             (k (task-handle (spawn-effect-computation desc) task-base #f #f #f))]
            [(await-effect? desc)
             (define handle (await-effect-handle desc))
             (cond
                 [(task-handle-done? handle)
                  (deliver-outcome handle k)]
                 [else
                  (define o
                      (run-to-outcome (task-handle-computation handle)
                          (body (task-handle-base handle))))
                  (set-task-handle-outcome! handle o)
                  (set-task-handle-done?! handle #t)
                  (deliver-outcome handle k)])]
            [(poll-effect? desc)
             (define handle (poll-effect-handle desc))
             (if (task-handle-done? handle)
                 (deliver-outcome handle k)
                 (k (task-running)))]
            [else (base desc k)]))

    ;; Type: (-> (-> Any (-> Any Free) Free) (-> Any (-> Any Free) Free))
    (define body (make-body h))
    h)

;; The answered handler waits on a semaphore around the wrapped handler's
;; answer, then resumes the caller's k once the lock is back.
;; Type: (-> (-> Any (-> Any Free) Free) (-> Any (-> Any Free) Free))
;; Impure: waits on a semaphore around the wrapped handler's answer; raises exn:fail when it does not resume its k exactly once.
(define (make-locked-handler wrapped)
    (define lock (make-semaphore 1))
    (lambda (desc k)
        (define resumed 0)
        (define answer #f)
        ;; Type: (-> Any Free)
        (define (stand-in v)
            (set! resumed (add1 resumed))
            (cond
                [(= resumed 1)
                 (set! answer v)
                 (return v)]
                [else
                 (error 'make-locked-handler
                     "the wrapped handler resumed its k more than once")]))
        (dynamic-wind
            (lambda () (semaphore-wait lock))
            (lambda ()
                (wrapped desc stand-in)
                (when (zero? resumed)
                    (error 'make-locked-handler
                        "the wrapped handler did not resume its k")))
            (lambda () (semaphore-post lock)))
        (k answer)))


(module+ test
    (require
        rackunit
        racket/match
        "effects/state-effect.rkt")

    ;; Type: (-> Box (-> Any (-> Any Free) Free))
    ;; Test handler that counts the descriptions it answers.
    (define ((counting-handler! box) desc k)
        (set-box! box (add1 (unbox box)))
        (k 'answered))

    ;; Type: (-> Any (-> Any (-> Any Free) Free))
    ;; Test handler that answers every description with a fixed value.
    (define ((echo-handler value) desc k)
        (k value))

    ;; Type: (-> (-> Any (-> Any Free) Free) (-> Any (-> Any Free) Free))
    ;; Multi-shot test handler: resumes the spawn continuation twice with the
    ;; same handle.
    (define (make-dup-handler task-handler)
        (define (dup desc k)
            (cond
                [(spawn-effect? desc)
                 (define handle
                     (match (task-handler desc (lambda (h) (return h)))
                         [(pure h) h]))
                 (return (list (run (k handle) dup)
                               (run (k handle) dup)))]
                [else (task-handler desc k)]))
        dup)

    ;; Type: (-> Semaphore (-> Any (-> Any Free) Free))
    ;; Test handler that blocks on 'wait-go and posts on 'post-go.
    (define ((wait-post-handler! go) desc k)
        (match desc
            ['wait-go (semaphore-wait go) (k 'unblocked)]
            ['post-go (semaphore-post go) (k 'posted)]
            [_ (error "unexpected effect")]))

    ;; Type: (-> Box (-> Any (-> Any Free) Free))
    ;; Test handler that records the thread it answers on.
    (define ((thread-recording-handler! box) desc k)
        (set-box! box (current-thread))
        (k 'recorded))

    ;; Type: (-> HashEq (-> Any (-> Any Free) Free))
    ;; Test handler that answers state effects from a mutable store.
    (define ((test-state-handler! store) desc k)
        (cond
            [(read-state-effect? desc)
             (k (hash-ref store (read-state-effect-key desc)))]
            [(write-state-effect? desc)
             (hash-set! store (write-state-effect-key desc)
                 (write-state-effect-value desc))
             (k (void))]
            [else (error "unexpected effect")]))

    ;; Type: (-> (-> Any (-> Any Free) Free))
    ;; Makes a state handler over a fresh store.
    (define (fresh-store-factory)
        (test-state-handler! (make-state-store '((n . 0)))))

    ;; 11
    (test-case "await: should answer a task success when the task finishes"
        ;; Given
        (define program
            (do-m [h <- (spawn (return 41))]
                  [o <- (await h)]
                  (return o)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par (task-success 41))
        (check-equal? seq (task-success 41)))

    ;; 12
    (test-case "await: should answer a value the parent can use when the task succeeds"
        ;; Given
        (define program
            (do-m [h <- (spawn (return 41))]
                  [o <- (await h)]
                  (return (add1 (task-success-value o)))))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par 42)
        (check-equal? seq 42))

    ;; 13
    (test-case "await: should answer the wrapped handler's value when a task performs a non-task effect"
        ;; Given
        (define program
            (do-m [h <- (spawn (do-m [v <- (perform 'ask)] (return v)))]
                  [o <- (await h)]
                  (return o)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 7))))
        (define seq (run program (make-sequential-task-handler (echo-handler 7))))
        ;; Then
        (check-equal? par (task-success 7))
        (check-equal? seq (task-success 7)))

    ;; 14
    (test-case "await: should keep the failure in the outcome when the task fails"
        ;; Given
        (define (failing-task)
            (try (return #f) (return 'oops)))
        (define (await-program)
            (do-m [h <- (spawn (failing-task))]
                  [o <- (await h)]
                  (return o)))
        (define par-h (make-parallel-task-handler (echo-handler 0)))
        (define seq-h (make-sequential-task-handler (echo-handler 0)))
        ;; When
        (define par (run (await-program) par-h))
        (define seq (run (await-program) seq-h))
        (define caught-par (run (catch (await-program)) par-h))
        (define caught-seq (run (catch (await-program)) seq-h))
        ;; Then
        (check-equal? par (task-failure 'oops))
        (check-equal? seq (task-failure 'oops))
        (check-equal? caught-par (task-failure 'oops))
        (check-equal? caught-seq (task-failure 'oops)))

    ;; 15
    (test-case "await: should answer the fallback's effectful value when a failing task has an effectful fallback"
        ;; Given
        (define (failing-task)
            (try (return #f)
                 (do-m [v <- (perform 'ask)] (return v))))
        (define program
            (do-m [h <- (spawn (failing-task))]
                  [o <- (await h)]
                  (return o)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 9))))
        (define seq (run program (make-sequential-task-handler (echo-handler 9))))
        ;; Then
        (check-equal? par (task-failure 9))
        (check-equal? seq (task-failure 9)))

    ;; 16
    (test-case "await: should answer a task success when the task's value is #f"
        ;; Given
        (define program
            (do-m [h <- (spawn (return #f))]
                  [o <- (await h)]
                  (return o)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par (task-success #f))
        (check-equal? seq (task-success #f)))

    ;; 17
    (test-case "await: should answer the same outcome twice when a task is awaited twice"
        ;; Given
        (define par-count (box 0))
        (define seq-count (box 0))
        (define program
            (do-m [h <- (spawn (do-m [_ <- (perform 'count)] (return 'done)))]
                  [a <- (await h)]
                  [b <- (await h)]
                  (return (list a b))))
        ;; When
        (define par
            (run program (make-parallel-task-handler (counting-handler! par-count))))
        (define seq
            (run program (make-sequential-task-handler (counting-handler! seq-count))))
        ;; Then
        (check-equal? par (list (task-success 'done) (task-success 'done)))
        (check-equal? seq (list (task-success 'done) (task-success 'done)))
        (check-equal? (unbox par-count) 1)
        (check-equal? (unbox seq-count) 1))

    ;; 18
    (test-case "poll: should answer task-running before the run and the outcome after when awaiting between polls"
        ;; Given
        (define count (box 0))
        (define program
            (do-m [h <- (spawn (do-m [_ <- (perform 'count)] (return 'done)))]
                  [r <- (poll h)]
                  [o <- (await h)]
                  [r2 <- (poll h)]
                  (return (list r o r2))))
        ;; When
        (define result
            (run program (make-sequential-task-handler (counting-handler! count))))
        ;; Then
        (check-equal? result
            (list (task-running) (task-success 'done) (task-success 'done)))
        (check-equal? (unbox count) 1))

    ;; 19
    (test-case "poll: should answer task-running while the task blocks and the outcome when it has finished"
        ;; Given
        (define go (make-semaphore 0))
        (define program
            (do-m [h <- (spawn (do-m [v <- (perform 'wait-go)] (return v)))]
                  [r <- (poll h)]
                  [_ <- (perform 'post-go)]
                  [o <- (await h)]
                  [r2 <- (poll h)]
                  (return (list r o r2))))
        ;; When
        (define result
            (run program (make-parallel-task-handler (wait-post-handler! go))))
        ;; Then
        (check-equal? result
            (list (task-running)
                  (task-success 'unblocked)
                  (task-success 'unblocked))))

    ;; 20
    (test-case "poll: should answer task-running when the poll is caught by catch"
        ;; Given
        (define program
            (catch
                (do-m [h <- (spawn (return 'done))]
                      [o <- (poll h)]
                      (return o))))
        ;; When
        (define result
            (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? result (task-running)))

    ;; 21
    (test-case "await: should answer the same outcome to each branch when a multi-shot continuation awaits one handle"
        ;; Given
        (define count (box 0))
        (define program
            (do-m [h <- (spawn (do-m [_ <- (perform 'count)] (return 'done)))]
                  [o <- (await h)]
                  (return o)))
        (define handler
            (make-dup-handler (make-sequential-task-handler (counting-handler! count))))
        ;; When
        (define result (run program handler))
        ;; Then
        (check-equal? result
            (list (task-success 'done) (task-success 'done)))
        (check-equal? (unbox count) 1))

    ;; 22
    (test-case "poll: should not run the task when polling an unrun task"
        ;; Given
        (define count (box 0))
        (define handler
            (make-sequential-task-handler (counting-handler! count)))
        (define (task)
            (do-m [_ <- (perform 'count)] (return 'done)))
        ;; When
        (define running
            (run (do-m [h <- (spawn (task))]
                       [r <- (poll h)]
                       (return r))
                 handler))
        ;; Then
        (check-equal? running (task-running))
        (check-equal? (unbox count) 0)
        ;; When
        (define done
            (run (do-m [h <- (spawn (task))]
                       [o <- (await h)]
                       (return o))
                 handler))
        ;; Then
        (check-equal? done (task-success 'done))
        (check-equal? (unbox count) 1))

    ;; 23
    (test-case "await: should wait for a later task when a task blocks on another"
        ;; Given
        (define go-par (make-semaphore 0))
        (define go-seq (make-semaphore 0))
        (define program
            (do-m [h1 <- (spawn (do-m [v <- (perform 'wait-go)] (return 't1)))]
                  [h2 <- (spawn (do-m [_ <- (perform 'post-go)] (return 't2)))]
                  [o2 <- (await h2)]
                  [o1 <- (await h1)]
                  (return (list o1 o2))))
        ;; When
        (define par
            (run program (make-parallel-task-handler (wait-post-handler! go-par))))
        (define seq
            (run program (make-sequential-task-handler (wait-post-handler! go-seq))))
        ;; Then
        (check-equal? par (list (task-success 't1) (task-success 't2)))
        (check-equal? seq (list (task-success 't1) (task-success 't2))))

    ;; 24
    (test-case "map-par: should answer the outcomes in input order when the elements succeed"
        ;; Given
        (define program
            (map-par (lambda (x) (return (* x x))) '(1 2 3 4)))
        (define expected
            (list (task-success 1) (task-success 4)
                  (task-success 9) (task-success 16)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par expected)
        (check-equal? seq expected))

    ;; 25
    (test-case "map-par: should answer the empty list when given no elements"
        ;; Given
        (define program (map-par (lambda (x) (return x)) '()))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par '())
        (check-equal? seq '()))

    ;; 26
    (test-case "run-par: should answer the outcomes in the given order when the computations succeed"
        ;; Given
        (define program
            (run-par (list (return 'a) (return 'b) (return 'c))))
        (define expected
            (list (task-success 'a) (task-success 'b) (task-success 'c)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par expected)
        (check-equal? seq expected))

    ;; 27
    (test-case "run-par: should answer the empty list when given no computations"
        ;; Given
        (define program (run-par '()))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par '())
        (check-equal? seq '()))

    ;; 28
    (test-case "run-par: should answer every outcome when one task fails"
        ;; Given
        (define program
            (run-par (list (return 1)
                           (try (return #f) (return 'bad))
                           (return 3))))
        (define expected
            (list (task-success 1) (task-failure 'bad) (task-success 3)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par expected)
        (check-equal? seq expected))

    ;; 29
    (test-case "run-par: should let siblings run to completion when the middle task fails"
        ;; Given
        (define par-count (box 0))
        (define seq-count (box 0))
        (define (sibling i)
            (if (= i 1)
                (try (return #f) (return 'mid-failed))
                (do-m [_ <- (perform 'count)] (return i))))
        (define program
            (run-par (list (sibling 0) (sibling 1) (sibling 2))))
        (define expected
            (list (task-success 0) (task-failure 'mid-failed) (task-success 2)))
        ;; When
        (define par
            (run program
                 (make-parallel-task-handler
                     (make-locked-handler (counting-handler! par-count)))))
        (define seq
            (run program
                 (make-sequential-task-handler (counting-handler! seq-count))))
        ;; Then
        (check-equal? par expected)
        (check-equal? seq expected)
        (check-equal? (unbox par-count) 2)
        (check-equal? (unbox seq-count) 2))

    ;; 30
    (test-case "await: should nest the outcomes when a task spawns and awaits a sub-task"
        ;; Given
        (define (outer)
            (do-m [sh <- (spawn (return 'v))]
                  [so <- (await sh)]
                  (return so)))
        (define program
            (do-m [h <- (spawn (outer))]
                  [o <- (await h)]
                  (return o)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par (task-success (task-success 'v)))
        (check-equal? seq (task-success (task-success 'v))))

    ;; 31
    (test-case "collect-par: should answer the values when a parallel map succeeds"
        ;; Given
        (define program
            (do-m [os <- (map-par (lambda (x) (return (* 2 x))) '(1 2 3))]
                  [vs <- (collect-par os)]
                  (return vs)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par '(2 4 6))
        (check-equal? seq '(2 4 6)))

    ;; 32
    (test-case "collect-par: should answer the leftmost failing value when an outcome fails"
        ;; Given
        (define ms
            (list (return 1) (try (return #f) (return 'mid)) (return 3)))
        (define program
            (do-m [os <- (run-par ms)]
                  [vs <- (collect-par os)]
                  (return vs)))
        (define seen (box #f))
        ;; Type: (-> Any (-> Any Free) Free)
        (define (recording-base desc k)
            (cond
                [(try-failure-effect? desc)
                 (set-box! seen desc)
                 (return 'caught-by-base)]
                [else (k 'answered)]))
        ;; When
        (define par (run (catch program) (make-parallel-task-handler (echo-handler 0))))
        (define seq (run (catch program) (make-sequential-task-handler (echo-handler 0))))
        (define par-raw (run program (make-parallel-task-handler recording-base)))
        (define seq-raw (run program (make-sequential-task-handler recording-base)))
        ;; Then
        (check-equal? par 'mid)
        (check-equal? seq 'mid)
        (check-equal? par-raw 'caught-by-base)
        (check-equal? seq-raw 'caught-by-base)
        (check-true (try-failure-effect? (unbox seen)))
        (check-equal? (try-failure-effect-fallback (unbox seen)) (pure 'mid)))

    ;; 33
    (test-case "make-parallel-task-handler: should answer the same outcomes as the sequential handler when running the same program"
        ;; Given
        (define (parity-program)
            (do-m [h <- (spawn (try (return #f) (return 'oops)))]
                  [o1 <- (await h)]
                  [p1 <- (poll h)]
                  [os <- (map-par (lambda (x)
                                    (if (= x 2)
                                        (try (return #f) (return 'two-failed))
                                        (return (* x 10))))
                                  '(1 2 3))]
                  [vs <- (collect-par (list (task-success 'a) (task-success 'b)))]
                  [h2 <- (spawn (return 41))]
                  [o2 <- (await h2)]
                  (return (list o1 p1 os vs (task-success-value o2)))))
        (define expected
            (list (task-failure 'oops)
                  (task-failure 'oops)
                  (list (task-success 10) (task-failure 'two-failed) (task-success 30))
                  '(a b)
                  41))
        ;; When
        (define par
            (run (parity-program) (make-parallel-task-handler (echo-handler 0))))
        (define seq
            (run (parity-program) (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-equal? par expected)
        (check-equal? seq expected))

    ;; 34
    (test-case "make-parallel-task-handler: should delegate an unknown description to the wrapped handler when the parent program performs one"
        ;; Given
        (define program
            (do-m [v <- (perform 'ask)] (return v)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 5))))
        (define seq (run program (make-sequential-task-handler (echo-handler 5))))
        ;; Then
        (check-equal? par 5)
        (check-equal? seq 5))

    ;; 35
    (test-case "make-locked-handler: should give the same final state and results as a sequential run when many tasks share a stateful handler"
        ;; Given
        (define n 10)
        ;; Type: (-> Box (-> Any (-> Any Free) Free))
        (define ((bump-handler! store) desc k)
            (match desc
                ['bump (set-box! store (add1 (unbox store))) (k (void))]
                [_ (error "unexpected effect")]))
        (define (bump-program)
            (run-par
                (for/list ([i (in-range n)])
                    (do-m [_ <- (perform 'bump)] (return i)))))
        (define par-store (box 0))
        (define seq-store (box 0))
        (define expected
            (for/list ([i (in-range n)]) (task-success i)))
        ;; When
        (define par
            (run (bump-program)
                 (make-parallel-task-handler
                     (make-locked-handler (bump-handler! par-store)))))
        (define seq
            (run (bump-program)
                 (make-sequential-task-handler (bump-handler! seq-store))))
        ;; Then
        (check-equal? par expected)
        (check-equal? seq expected)
        (check-equal? (unbox par-store) n)
        (check-equal? (unbox seq-store) n))

    ;; 36
    (test-case "make-locked-handler: should serialise the answer but not the continuation when the continuations overlap"
        ;; Given
        (define n 4)
        (define go (make-semaphore 0))
        (define reserved (box 0))
        (define released (box 0))
        ;; Type: (-> Any (-> Any Free) Free)
        (define (store-handler desc k)
            (match desc
                ['reserve
                 (set-box! reserved (add1 (unbox reserved)))
                 (when (= (unbox reserved) n)
                     (for ([i (in-range n)]) (semaphore-post go)))
                 (k (unbox reserved))]
                ['release
                 (set-box! released (add1 (unbox released)))
                 (k 'released)]
                [_ (error "unexpected effect")]))
        (define locked (make-locked-handler store-handler))
        ;; Type: (-> Any (-> Any Free) Free)
        ;; The continuation's wait bypasses the lock; store effects run through
        ;; it.
        (define (base desc k)
            (cond
                [(eq? desc 'overlap-wait)
                 (define woke (sync/timeout 5.0 go))
                 (k (if woke 'woke 'timed-out))]
                [else (locked desc k)]))
        (define (overlap-task)
            (do-m [r <- (perform 'reserve)]
                  [w <- (perform 'overlap-wait)]
                  [_ <- (perform 'release)]
                  (return w)))
        ;; When
        (define result
            (run (run-par (for/list ([i (in-range n)]) (overlap-task)))
                 (make-parallel-task-handler base)))
        ;; Then
        (check-equal? (unbox reserved) n)
        (check-equal? (unbox released) n)
        (for ([o (in-list result)])
            (check-equal? o (task-success 'woke))))

    ;; 37
    (test-case "make-locked-handler: should release the lock when the wrapped handler raises"
        ;; Given
        ;; Type: (-> Any (-> Any Free) Free)
        (define (boom-handler desc k)
            (raise 'boom))
        (define locked (make-locked-handler boom-handler))
        (define captured (box '()))
        ;; Type: (-> Any (-> Any Free) Free)
        (define (base desc k)
            (match desc
                [(list 'sync-both hs ...)
                 (for ([h (in-list hs)]) (thread-wait (task-handle-thread h)))
                 (set-box! captured hs)
                 (k 'synced)]
                [else (locked desc k)]))
        (define (boom-task i)
            (do-m [_ <- (perform 'anything)] (return i)))
        (define program
            (do-m [h1 <- (spawn (boom-task 1))]
                  [h2 <- (spawn (boom-task 2))]
                  [_ <- (perform (list 'sync-both h1 h2))]
                  [_ <- (await h1)]
                  (return 'unreachable)))
        ;; When
        (define result
            (with-handlers ([(lambda (e) (eq? e 'boom)) (lambda (e) 'propagated)])
                (run program (make-parallel-task-handler base))))
        ;; Then
        (check-equal? result 'propagated)
        (for ([h (in-list (unbox captured))])
            (check-eq? (task-handle-outcome h) 'boom)))

    ;; 38
    (test-case "make-locked-handler: should raise a plain exn:fail when the wrapped handler is not single-shot"
        ;; Given
        ;; Type: (-> Any (-> Any Free) Free)
        (define (never-handler desc k)
            (return 'ignored))
        ;; Type: (-> Any (-> Any Free) Free)
        (define (twice-handler desc k)
            (k 1)
            (k 2))
        ;; When / Then
        (check-exn exn:fail?
            (lambda () (run (perform 'x) (make-locked-handler never-handler))))
        (check-exn exn:fail?
            (lambda () (run (perform 'x) (make-locked-handler twice-handler)))))

    ;; 39
    (test-case "make-parallel-task-handler: should isolate handler state between tasks when #:fresh is given"
        ;; Given
        (define program
            (run-par
                (list
                 (do-m [_ <- (write-state 'n 42)] (return 'wrote))
                 (do-m [v <- (read-state 'n)] (return v)))))
        (define expected-fresh
            (list (task-success 'wrote) (task-success 0)))
        ;; When
        (define par
            (run program
                 (make-parallel-task-handler (fresh-store-factory)
                     #:fresh fresh-store-factory)))
        (define seq
            (run program
                 (make-sequential-task-handler (fresh-store-factory)
                     #:fresh fresh-store-factory)))
        (define shared
            (run program
                 (make-sequential-task-handler
                     (test-state-handler! (make-state-store '((n . 0)))))))
        ;; Then
        (check-equal? par expected-fresh)
        (check-equal? seq expected-fresh)
        (check-equal? shared (list (task-success 'wrote) (task-success 42))))

    ;; 40
    (test-case "make-sequential-task-handler: should accept a #:fresh factory and answer the shared run's outcomes when tasks read their own writes"
        ;; Given
        (define (state-task i)
            (do-m [_ <- (write-state 'n i)]
                  [v <- (read-state 'n)]
                  (return (list i v))))
        (define program
            (run-par (list (state-task 1) (state-task 2) (state-task 3))))
        (define expected
            (list (task-success '(1 1))
                  (task-success '(2 2))
                  (task-success '(3 3))))
        ;; When
        (define par
            (run program
                 (make-parallel-task-handler (fresh-store-factory)
                     #:fresh fresh-store-factory)))
        (define seq
            (run program
                 (make-sequential-task-handler (fresh-store-factory)
                     #:fresh fresh-store-factory)))
        (define shared
            (run program
                 (make-sequential-task-handler
                     (test-state-handler! (make-state-store '((n . 0)))))))
        ;; Then
        (check-equal? par expected)
        (check-equal? seq expected)
        (check-equal? shared expected))

    ;; 41
    (test-case "await: should re-raise the task's exception when the task raises"
        ;; Given
        (define (raising-task)
            (do-m [_ <- (perform 'ask)]
                  (raise 'sym)))
        (define (await-program)
            (do-m [h <- (spawn (raising-task))]
                  [o <- (await h)]
                  (return o)))
        ;; Type: (-> Any (-> Any Free) Free)
        (define (sync-echo desc k)
            (match desc
                [(list 'sync h)
                 (thread-wait (task-handle-thread h))
                 (k 'synced)]
                [_ (k 'answered)]))
        ;; When / Then
        (check-exn (lambda (e) (eq? e 'sym))
            (lambda ()
                (run (await-program)
                     (make-parallel-task-handler (echo-handler 0)))))
        (check-exn (lambda (e) (eq? e 'sym))
            (lambda ()
                (run (await-program)
                     (make-sequential-task-handler (echo-handler 0)))))
        (check-exn (lambda (e) (eq? e 'sym))
            (lambda ()
                (run (do-m [h <- (spawn (raising-task))]
                           [_ <- (perform (list 'sync h))]
                           [o <- (poll h)]
                           (return o))
                     (make-parallel-task-handler sync-echo)))))

    ;; 42
    (test-case "task-handle?: should answer true when given a handle answered by spawn"
        ;; Given
        (define program
            (do-m [h <- (spawn (return 1))] (return h)))
        ;; When
        (define par (run program (make-parallel-task-handler (echo-handler 0))))
        (define seq (run program (make-sequential-task-handler (echo-handler 0))))
        ;; Then
        (check-true (task-handle? par))
        (check-true (task-handle? seq)))

    ;; 43
    (test-case "make-parallel-task-handler: should run the task's work on the task's thread when a task performs an effect"
        ;; Given
        (define recorder (box #f))
        (define program
            (do-m [h <- (spawn (do-m [_ <- (perform 'record)] (return 'done)))]
                  [o <- (await h)]
                  (return o)))
        (define parent (current-thread))
        ;; When
        (run program (make-parallel-task-handler (thread-recording-handler! recorder)))
        (define par-thread (unbox recorder))
        (set-box! recorder #f)
        (run program (make-sequential-task-handler (thread-recording-handler! recorder)))
        (define seq-thread (unbox recorder))
        ;; Then
        (check-false (eq? par-thread parent))
        (check-eq? seq-thread parent)))
