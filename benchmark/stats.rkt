#lang racket/base

(provide
 (struct-out summary)
 (struct-out fit)
 summarise
 spread-flag?
 rerun-point?
 split-positive
 log-log-slope)

(require
 racket/list)

;; quartile-method is the symbol 'R-7.
(struct summary (median min max iqr quartile-method) #:transparent)

;; slope: Real, range: (Pair Natural Natural), the first and last n of the fit.
(struct fit (slope range) #:transparent)

;; Type: (-> (Listof Real) summary)
;; Raises exn:fail when the argument is not a non-empty list of reals.
(define (summarise samples)
  (unless (and (list? samples) (pair? samples) (andmap real? samples))
    (raise-argument-error 'summarise "(non-empty listof real?)" samples))
  (define sorted (list->vector (sort samples <)))
  (define q1 (quantile sorted 1/4))
  (define q3 (quantile sorted 3/4))
  (summary (quantile sorted 1/2)
           (vector-ref sorted 0)
           (vector-ref sorted (sub1 (vector-length sorted)))
           (- q3 q1)
           'R-7))

;; R-7 quantile: linear interpolation between order statistics.
;; Type: (-> (Vectorof Real) Real Real)
(define (quantile sorted p)
  (define h (* (sub1 (vector-length sorted)) p))
  (define lo (floor h))
  (define low (vector-ref sorted (inexact->exact lo)))
  (if (= h lo)
      low
      (+ low (* (- h lo) (- (vector-ref sorted (add1 (inexact->exact lo))) low)))))

;; Type: (->* (summary) (Real) Boolean)
(define (spread-flag? s [threshold 0.20])
  (> (summary-iqr s) (* threshold (summary-median s))))

;; Type: (-> summary Boolean)
(define (rerun-point? s)
  (spread-flag? s))

;; Type: (-> (Listof (Pair Natural Real)) (Values (Listof (Pair Natural Real)) (Listof (Pair Natural Real))))
(define (split-positive points)
  (partition (lambda (p) (> (cdr p) 0)) points))

;; Type: (->* ((Listof Natural) (Listof Real)) (#:range (U (Pair Natural Natural) #f)) fit)
;; Raises exn:fail when the lengths differ, fewer than two points are fitted, or a fitted time is not positive.
(define (log-log-slope ns times #:range [range #f])
  (unless (= (length ns) (length times))
    (raise-arguments-error 'log-log-slope "ns and times differ in length"
                           "ns" ns "times" times))
  (define points
    (for/list ([n (in-list ns)] [t (in-list times)]
               #:when (or (not range) (<= (car range) n (cdr range))))
      (cons n t)))
  (when (< (length points) 2)
    (raise-arguments-error 'log-log-slope "fewer than two points to fit" "points" points))
  (unless (andmap (lambda (p) (> (cdr p) 0)) points)
    (raise-arguments-error 'log-log-slope "a time is not positive" "points" points))
  (define xs (map (lambda (p) (log2 (car p))) points))
  (define ys (map (lambda (p) (log2 (cdr p))) points))
  (fit (least-squares-slope xs ys)
       (cons (car (first points)) (car (last points)))))

;; Type: (-> Real Real)
(define (log2 x)
  (/ (log (exact->inexact x)) (log 2.0)))

;; Type: (-> (Listof Real) (Listof Real) Real)
(define (least-squares-slope xs ys)
  (define count (length xs))
  (define mean-x (/ (apply + xs) count))
  (define mean-y (/ (apply + ys) count))
  (define sxx (for/sum ([x (in-list xs)]) (sqr (- x mean-x))))
  (define sxy (for/sum ([x (in-list xs)] [y (in-list ys)]) (* (- x mean-x) (- y mean-y))))
  (when (zero? sxx)
    (raise-arguments-error 'log-log-slope "all sizes are equal" "xs" xs))
  (/ sxy sxx))

;; Type: (-> Real Real)
(define (sqr x) (* x x))

(module+ test
  (require rackunit)

  ;; A summary built by hand from a median and an iqr.
  (define (s median iqr) (summary median median median iqr 'R-7))

  ;; ------------------------------------------------------------
  ;; summarise
  ;; ------------------------------------------------------------

  (test-case "summarise: should give median 3, min 1, max 5, iqr 2 when given (1 2 3 4 5)"
    ;; Given
    (define samples '(1 2 3 4 5))
    ;; When
    (define result (summarise samples))
    ;; Then
    (check-true (summary? result))
    (check-equal? (summary-median result) 3)
    (check-equal? (summary-min result) 1)
    (check-equal? (summary-max result) 5)
    (check-equal? (summary-iqr result) 2))

  (test-case "summarise: should interpolate quartiles when the count is even"
    (define result (summarise '(1 2 3 4)))
    (check-= (summary-median result) 2.5 1e-9)
    (check-equal? (summary-min result) 1)
    (check-equal? (summary-max result) 4)
    (check-= (summary-iqr result) 1.5 1e-9))

  (test-case "summarise: should handle two samples"
    (define result (summarise '(10 20)))
    (check-= (summary-median result) 15 1e-9)
    (check-equal? (summary-min result) 10)
    (check-equal? (summary-max result) 20)
    (check-= (summary-iqr result) 5 1e-9))

  (test-case "summarise: should return the value for every field and iqr 0 when given one sample"
    (define result (summarise '(7)))
    (check-equal? (summary-median result) 7)
    (check-equal? (summary-min result) 7)
    (check-equal? (summary-max result) 7)
    (check-equal? (summary-iqr result) 0))

  (test-case "summarise: should sort and not mutate the input when the samples are unordered"
    ;; Given
    (define samples (list 5 1 4 2 3))
    ;; When
    (define result (summarise samples))
    ;; Then
    (check-equal? result (summarise '(1 2 3 4 5)))
    (check-equal? samples '(5 1 4 2 3)))

  (test-case "summarise: should give iqr 0 when all samples are equal"
    (define result (summarise '(4 4 4 4)))
    (check-equal? (summary-median result) 4)
    (check-equal? (summary-min result) 4)
    (check-equal? (summary-max result) 4)
    (check-equal? (summary-iqr result) 0))

  (test-case "summarise: should accept inexact reals"
    (define result (summarise '(0.5 1.5 2.5 3.5)))
    (check-= (summary-median result) 2.0 1e-9)
    (check-= (summary-iqr result) 1.5 1e-9))

  (test-case "summarise: should accept negative samples"
    (define result (summarise '(-3 -1 -2)))
    (check-equal? (summary-median result) -2)
    (check-equal? (summary-min result) -3)
    (check-equal? (summary-max result) -1)
    (check-equal? (summary-iqr result) 1))

  (test-case "summarise: should record quartile-method 'R-7 when called on any list"
    (check-equal? (summary-quartile-method (summarise '(7))) 'R-7)
    (check-equal? (summary-quartile-method (summarise '(1 2 3 4 5))) 'R-7))

  (test-case "summarise: should raise when given the empty list"
    (check-exn exn:fail? (lambda () (summarise '()))))

  (test-case "summarise: should raise when a sample is not a real number"
    (check-exn exn:fail? (lambda () (summarise '(1 "a" 3))))
    (check-exn exn:fail? (lambda () (summarise 5))))

  ;; ------------------------------------------------------------
  ;; spread-flag?
  ;; ------------------------------------------------------------

  (test-case "spread-flag?: should return #f when iqr is below 20% of the median"
    (check-false (spread-flag? (s 10 1.5))))

  (test-case "spread-flag?: should return #t when iqr exceeds 20% of the median"
    (check-true (spread-flag? (s 10 2.5))))

  (test-case "spread-flag?: should return #f when iqr equals the threshold times the median"
    (check-false (spread-flag? (s 10 2))))

  (test-case "spread-flag?: should use the given threshold when one is passed"
    (check-true (spread-flag? (s 10 4)))
    (check-false (spread-flag? (s 10 4) 0.5)))

  (test-case "spread-flag?: should return #f when median and iqr are both 0"
    (check-false (spread-flag? (s 0 0))))

  (test-case "spread-flag?: should return #t when the median is 0 and iqr is positive"
    (check-true (spread-flag? (s 0 1))))

  (test-case "spread-flag?: should flag any positive iqr when the threshold is 0"
    (check-false (spread-flag? (s 10 0) 0))
    (check-true (spread-flag? (s 10 0.1) 0)))

  ;; ------------------------------------------------------------
  ;; log-log-slope
  ;; ------------------------------------------------------------

  (test-case "log-log-slope: should give slope 1 when time grows linearly"
    (define result (log-log-slope '(64 128 256 512) '(64 128 256 512)))
    (check-true (fit? result))
    (check-= (fit-slope result) 1.0 1e-9)
    (check-equal? (fit-range result) '(64 . 512)))

  (test-case "log-log-slope: should give slope 2 when time grows with n squared"
    (define result (log-log-slope '(64 128 256 512) '(4096 16384 65536 262144)))
    (check-= (fit-slope result) 2.0 1e-9))

  (test-case "log-log-slope: should give slope 0 when times are constant"
    (define result (log-log-slope '(64 128 256 512) '(5 5 5 5)))
    (check-= (fit-slope result) 0.0 1e-9))

  (test-case "log-log-slope: should give 1.5 when ns are not powers of two"
    (define result (log-log-slope '(10 100 1000) '(31.6227766 1000 31622.7766)))
    (check-= (fit-slope result) 1.5 1e-6))

  (test-case "log-log-slope: should fit only the given range when #:range is a pair"
    (define result (log-log-slope '(64 128 256 512) '(1000 2 4 8) #:range (cons 128 512)))
    (check-= (fit-slope result) 1.0 1e-9)
    (check-equal? (fit-range result) '(128 . 512)))

  (test-case "log-log-slope: should fit the whole series when #:range is #f"
    (define result (log-log-slope '(64 128 256 512) '(1000 2 4 8) #:range #f))
    (check-true (> (abs (- (fit-slope result) 1.0)) 0.1))
    (check-equal? (fit-range result) '(64 . 512)))

  (test-case "log-log-slope: should fit the upper half when called on it"
    (define ns '(64 128 256 512))
    (define times '(1 2 8 32))
    (check-= (fit-slope (log-log-slope ns times #:range (cons 256 512))) 2.0 1e-9)
    (check-true (> (abs (- (fit-slope (log-log-slope ns times)) 2.0)) 0.1)))

  (test-case "log-log-slope: should accept exactly two points"
    (define result (log-log-slope '(64 128) '(3 6)))
    (check-= (fit-slope result) 1.0 1e-9)
    (check-equal? (fit-range result) '(64 . 128)))

  (test-case "log-log-slope: should accept inexact times"
    (define result (log-log-slope '(64 128 256 512) '(0.001 0.002 0.004 0.008)))
    (check-= (fit-slope result) 1.0 1e-9))

  (test-case "log-log-slope: should raise when given one point"
    (check-exn exn:fail? (lambda () (log-log-slope '(64) '(5)))))

  (test-case "log-log-slope: should raise when given no points"
    (check-exn exn:fail? (lambda () (log-log-slope '() '()))))

  (test-case "log-log-slope: should raise when the range holds one point"
    (check-exn exn:fail?
               (lambda () (log-log-slope '(64 128 256) '(1 2 4) #:range (cons 256 256)))))

  (test-case "log-log-slope: should raise when a time is zero"
    (check-exn exn:fail? (lambda () (log-log-slope '(64 128 256) '(1 0 4)))))

  (test-case "log-log-slope: should raise when a time is negative"
    (check-exn exn:fail? (lambda () (log-log-slope '(64 128 256) '(1 -2 4)))))

  (test-case "log-log-slope: should raise when ns and times differ in length"
    (check-exn exn:fail? (lambda () (log-log-slope '(64 128) '(1 2 4)))))

  ;; ------------------------------------------------------------
  ;; rerun-point?
  ;; ------------------------------------------------------------

  (test-case "rerun-point?: should return #t when the summary is flagged"
    (check-true (rerun-point? (s 10 3))))

  (test-case "rerun-point?: should return #f when the summary is not flagged"
    (check-false (rerun-point? (s 10 1))))

  (test-case "rerun-point?: should return #f when iqr equals 20% of the median"
    (check-false (rerun-point? (s 10 2))))

  (test-case "rerun-point?: should return #f when median and iqr are both 0"
    (check-false (rerun-point? (s 0 0))))

  (test-case "rerun-point?: should raise when the argument is not a summary"
    (check-exn exn:fail? (lambda () (rerun-point? 5))))

  ;; ------------------------------------------------------------
  ;; split-positive
  ;; ------------------------------------------------------------

  (define (split points)
    (call-with-values (lambda () (split-positive points)) list))

  (test-case "split-positive: should keep all points when every median is positive"
    (check-equal? (split '((64 . 1.5) (128 . 3))) '(((64 . 1.5) (128 . 3)) ())))

  (test-case "split-positive: should exclude a zero median"
    (check-equal? (split '((64 . 0) (128 . 3))) '(((128 . 3)) ((64 . 0)))))

  (test-case "split-positive: should exclude a negative median"
    (check-equal? (split '((64 . -0.5) (128 . 2) (256 . 4)))
                  '(((128 . 2) (256 . 4)) ((64 . -0.5)))))

  (test-case "split-positive: should exclude everything when no median is positive"
    (check-equal? (split '((64 . 0) (128 . -1))) '(() ((64 . 0) (128 . -1)))))

  (test-case "split-positive: should return two empty lists when given none"
    (check-equal? (split '()) '(() ())))

  (test-case "split-positive: should keep the original order in both lists"
    (check-equal? (split '((64 . 1) (128 . 0) (256 . 2) (512 . -1)))
                  '(((64 . 1) (256 . 2)) ((128 . 0) (512 . -1)))))

  (test-case "split-positive: should keep a single positive point"
    (check-equal? (split '((64 . 2))) '(((64 . 2)) ()))))
