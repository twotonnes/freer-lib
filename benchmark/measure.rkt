#lang racket/base

(provide
 (struct-out sample)
 time-run
 measure-point
 empty-run-cost)

(require
 "stats.rkt")

;; times: milliseconds, bytes: allocated bytes, gcs: GC milliseconds (each a list,
;; one entry per repetition, less the empty-run cost); ops: operations per timed
;; call; batch: the batch factor.
(struct sample (times bytes gcs ops batch) #:transparent)

(define warm-up-calls 3)
(define default-repetitions 15)
(define empty-run-repetitions 15)
(define pilot-target-ms 1.0)
(define max-batch (expt 2 24))

;; Runs the thunk once between the three readings.
;; Type: (-> (-> Any) (Values Real Real Real))
;; Impure: collects garbage, reads the clock and the counters, calls the thunk.
(define (bracket! thunk)
  (collect-garbage)
  (define bytes-before (current-memory-use 'cumulative))
  (define gc-before (current-gc-milliseconds))
  (define time-before (current-inexact-monotonic-milliseconds))
  (thunk)
  (define time-after (current-inexact-monotonic-milliseconds))
  (define gc-after (current-gc-milliseconds))
  (define bytes-after (current-memory-use 'cumulative))
  (values (- time-after time-before)
          (- bytes-after bytes-before)
          (- gc-after gc-before)))

;; Type: (-> (-> Any) Natural (Values (Listof Real) (Listof Real) (Listof Real)))
;; Collects n brackets of the thunk as three lists (times, bytes, gcs).
;; Impure: see bracket!.
(define (bracket-lists! thunk n)
  (define rows
    (for/list ([i (in-range n)])
      (call-with-values (lambda () (bracket! thunk)) list)))
  (values (map car rows) (map cadr rows) (map caddr rows)))

(define empty-cost (box #f))

;; The median time, bytes and GC of an empty timed run, measured once per session.
;; Type: (-> (Values Real Real Real))
;; Impure: collects garbage, reads the clock and the counters; caches the result.
(define (empty-run-cost)
  (unless (unbox empty-cost)
    (define-values (times bytes gcs) (bracket-lists! void empty-run-repetitions))
    (set-box! empty-cost
              (list (summary-median (summarise times))
                    (summary-median (summarise bytes))
                    (summary-median (summarise gcs)))))
  (apply values (unbox empty-cost)))

;; Type: (->* ((-> Any) Natural) (#:repetitions Natural) sample)
;; Impure: calls the thunk 3 + r times, collects garbage, reads the clock and the counters.
;; Raises exn:fail when repetitions is not a positive integer, and what the thunk raises.
(define (measure-point thunk ops #:repetitions [repetitions default-repetitions])
  (unless (exact-positive-integer? repetitions)
    (raise-argument-error 'measure-point "exact-positive-integer?" repetitions))
  (define-values (empty-time empty-bytes empty-gc) (empty-run-cost))
  (for ([i (in-range warm-up-calls)])
    (thunk))
  (define-values (times bytes gcs) (bracket-lists! thunk repetitions))
  (sample (map (lambda (t) (- t empty-time)) times)
          (map (lambda (b) (- b empty-bytes)) bytes)
          (map (lambda (g) (- g empty-gc)) gcs)
          ops
          1))

;; Chooses the smallest power of two b such that b calls take at least 1 ms.
;; Type: (-> (-> Any) Natural Natural)
;; Impure: calls the thunk and reads the clock. Raises what the thunk raises.
(define (time-run thunk ops-per-call)
  (let loop ([batch 1])
    (define start (current-inexact-monotonic-milliseconds))
    (for ([i (in-range batch)])
      (thunk))
    (define elapsed (- (current-inexact-monotonic-milliseconds) start))
    (if (or (>= elapsed pilot-target-ms) (>= batch max-batch))
        batch
        (loop (* 2 batch)))))

(module+ test
  (require rackunit)

  (define (noop) (void))

  ;; ------------------------------------------------------------
  ;; time-run
  ;; ------------------------------------------------------------

  (test-case "time-run: should return a positive exact integer"
    (check-true (exact-positive-integer? (time-run noop 1))))

  (test-case "time-run: should return more than 1 when the thunk is much shorter than 1 ms"
    (check-true (>= (time-run noop 1) 2)))

  (test-case "time-run: should return 1 when one call already takes over 1 ms"
    (check-equal? (time-run (lambda () (sleep 0.01)) 1) 1))

  (test-case "time-run: should propagate an exception raised by the thunk"
    (check-exn #rx"boom" (lambda () (time-run (lambda () (error "boom")) 1))))

  ;; ------------------------------------------------------------
  ;; measure-point
  ;; ------------------------------------------------------------

  (test-case "measure-point: should return lists of 9 times, bytes and GC values when #:repetitions is 9"
    (define s (measure-point noop 1 #:repetitions 9))
    (check-true (sample? s))
    (check-equal? (length (sample-times s)) 9)
    (check-equal? (length (sample-bytes s)) 9)
    (check-equal? (length (sample-gcs s)) 9))

  (test-case "measure-point: should record ops and batch factor 1"
    (define s (measure-point noop 7 #:repetitions 3))
    (check-equal? (sample-ops s) 7)
    (check-equal? (sample-batch s) 1))

  (test-case "measure-point: should call the thunk 3 warm-up times plus r timed times"
    (define calls 0)
    (measure-point (lambda () (set! calls (add1 calls))) 1 #:repetitions 9)
    (check-equal? calls 12))

  (test-case "measure-point: should return lists of one when #:repetitions is 1"
    (define calls 0)
    (define s (measure-point (lambda () (set! calls (add1 calls))) 1 #:repetitions 1))
    (check-equal? (length (sample-times s)) 1)
    (check-equal? (length (sample-bytes s)) 1)
    (check-equal? (length (sample-gcs s)) 1)
    (check-equal? calls 4))

  (test-case "measure-point: should record times that reflect the work"
    (define s (measure-point (lambda () (sleep 0.02)) 1 #:repetitions 3))
    (for ([t (in-list (sample-times s))])
      (check-true (>= t 15) (format "time ~a ms" t))))

  (test-case "measure-point: should record more bytes for an allocating thunk than a no-op thunk"
    ;; Given
    (define sink #f)
    (define (allocate) (set! sink (make-vector 100000 0)))
    ;; When
    (define allocating (measure-point allocate 1 #:repetitions 5))
    (define idle (measure-point noop 1 #:repetitions 5))
    ;; Then
    (check-true (> (summary-median (summarise (sample-bytes allocating)))
                   (summary-median (summarise (sample-bytes idle))))))

  (test-case "measure-point: should record real numbers in every list"
    (define s (measure-point noop 1 #:repetitions 5))
    (check-true (andmap real? (sample-times s)))
    (check-true (andmap real? (sample-bytes s)))
    (check-true (andmap real? (sample-gcs s))))

  (test-case "measure-point: should raise and call nothing when #:repetitions is 0"
    (define calls 0)
    (check-exn exn:fail?
               (lambda () (measure-point (lambda () (set! calls (add1 calls))) 1 #:repetitions 0)))
    (check-equal? calls 0))

  (test-case "measure-point: should raise when #:repetitions is negative or not an integer"
    (check-exn exn:fail? (lambda () (measure-point noop 1 #:repetitions -1)))
    (check-exn exn:fail? (lambda () (measure-point noop 1 #:repetitions 2.5))))

  (test-case "measure-point: should propagate an exception raised by the thunk"
    (check-exn #rx"boom"
               (lambda () (measure-point (lambda () (error "boom")) 1 #:repetitions 3))))

  ;; ------------------------------------------------------------
  ;; empty-run-cost
  ;; ------------------------------------------------------------

  (test-case "empty-run-cost: should return real time, bytes and GC values that are small"
    (define-values (time bytes gc) (empty-run-cost))
    (check-true (real? time))
    (check-true (real? bytes))
    (check-true (real? gc))
    (check-true (< time 5)))

  (test-case "measure-point: should subtract the empty-run cost when the thunk does nothing"
    (define s (measure-point noop 1 #:repetitions 15))
    (check-true (< (abs (summary-median (summarise (sample-times s)))) 0.5))))
