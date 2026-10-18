#lang racket/base

(provide
 run-study
 case-by-id)

(require
 "case.rkt"
 "environment.rkt"
 "measure.rkt"
 "micro.rkt"
 "report.rkt"
 "stats.rkt"
 "workloads.rkt")

(define default-repetitions 15)

;; Type: (-> (Listof bench-case))
(define (all-cases)
  (apply append
         (map (lambda (make-cases) (make-cases))
              (list w1-case w2-case w3-case w4-case w5-case
                    u1-case u2-case u3-case u4-case u5-case u6-case u7-case u8-case u9-case))))

;; The bench-cases (all variants) with the given id, or all cases when no id is given.
;; Type: (->* () ((U Symbol String)) (Listof bench-case))
;; Raises exn:fail when the id is unknown.
(define (case-by-id [id #f])
  (cond [(not id) (all-cases)]
        [else
         (define wanted (if (string? id) (string->symbol id) id))
         (define found
           (filter (lambda (c) (eq? (bench-case-id c) wanted)) (all-cases)))
         (when (null? found)
           (raise-arguments-error 'case-by-id "unknown case id" "id" id))
         found]))

;; Checks and measures each case in turn, writes the raw file of each finished case,
;; and finally summary.org and environment.rktd, all below current-output-root.
;; Type: (->* () (#:cases (Listof bench-case) #:repetitions Natural) (Listof case-result))
;; Impure: runs the cases (clock, GC, subprocesses) and writes files.
;; Raises exn:fail when repetitions is below 1, and what a case raises.
(define (run-study #:cases [cases (all-cases)] #:repetitions [repetitions default-repetitions])
  (unless (exact-positive-integer? repetitions)
    (raise-argument-error 'run-study "exact-positive-integer?" repetitions))
  (define start-environment (record-environment))
  (define results
    (for/list ([c (in-list cases)])
      (run-case c repetitions start-environment)))
  (write-summary results (finish-environment start-environment))
  results)

;; Type: (-> bench-case Natural (Listof Any) case-result)
;; Impure: see run-study.
(define (run-case c repetitions environment)
  (define mismatch
    (with-handlers ([exn:bench-mismatch? values])
      (case-check c)
      #f))
  (cond [mismatch (failed-result c mismatch)]
        [else
         (define result (measure-case c repetitions))
         (write-raw result environment)
         result]))

;; Type: (-> bench-case exn:bench-mismatch case-result)
(define (failed-result c mismatch)
  (case-result (bench-case-id c) (bench-case-variant c) '() '() '() '() '()
               (list (exn:bench-mismatch-id mismatch)
                     (exn:bench-mismatch-variant mismatch)
                     (exn:bench-mismatch-n mismatch))))

;; Type: (-> bench-case Natural case-result)
;; Impure: see run-study.
(define (measure-case c repetitions)
  (define sizes (bench-case-sizes c))
  (define monadic
    (for/list ([n (in-list sizes)])
      (measure-size (bench-case-monadic c) ((bench-case-ops c) n) n repetitions)))
  (define plain
    (for/list ([n (in-list sizes)])
      (measure-size (bench-case-plain c) ((bench-case-ops c) n) n repetitions)))
  (case-result (bench-case-id c) (bench-case-variant c) sizes
               (map car monadic) (map car plain)
               (map (lambda (m p) (cons (or (cadr m) (cadr p)) (or (cddr m) (cddr p))))
                    monadic plain)
               (excluded-sizes sizes (map car monadic) (map car plain))
               #f))

;; One point: ((cons sample summary) . (cons flagged? re-run?)), as (cons point flags).
;; Type: (-> (-> Natural (-> Any)) Natural Natural Natural (Pair (Pair sample summary) (Pair Boolean Boolean)))
;; Impure: see run-study.
(define (measure-size build ops n repetitions)
  (define thunk (build n))
  (define batch (time-run thunk ops))
  (define batched (lambda () (for ([i (in-range batch)]) (thunk))))
  (define (measure reps)
    (define s (measure-point batched (* batch ops) #:repetitions reps))
    (cons (sample (sample-times s) (sample-bytes s) (sample-gcs s) (sample-ops s) batch)
          (summarise (sample-times s))))
  (define first-point (measure repetitions))
  (if (rerun-point? (cdr first-point))
      (cons (measure (* 2 repetitions)) (cons #t #t))
      (cons first-point (cons #f #f))))

;; Sizes at which the monadic or the plain median per run is not positive.
;; Type: (-> (Listof Natural) (Listof (Pair sample summary)) (Listof (Pair sample summary)) (Listof Natural))
(define (excluded-sizes sizes monadic plain)
  (for/list ([n (in-list sizes)] [m (in-list monadic)] [p (in-list plain)]
             #:unless (and (> (summary-median (cdr m)) 0) (> (summary-median (cdr p)) 0)))
    n))

;; Type: (-> (Listof Any) (Listof Any))
;; Impure: reads /proc/loadavg through record-environment.
(define (finish-environment start-environment)
  (define load-end (cdr (assq 'load-end (record-environment))))
  (for/list ([entry (in-list start-environment)])
    (if (eq? (car entry) 'load-end) (cons 'load-end load-end) entry)))

(module+ main
  (define arguments (vector->list (current-command-line-arguments)))
  (define results (run-study #:cases (apply case-by-id arguments)))
  (printf "Wrote ~a cases to ~a\n" (length results) (current-output-root)))

(module+ test
  (require
   rackunit
   racket/file
   racket/list
   racket/port)

  (define-values (here-dir)
    (let-values ([(base name dir?) (split-path (variable-reference->module-source (#%variable-reference)))])
      base))
  (define data-dir (simplify-path (build-path here-dir 'up "research" "data")))

  (define (listing dir)
    (if (directory-exists? dir)
        (sort (map path->string (find-files (lambda (_) #t) dir)) string<?)
        '()))

  (define (call-with-temp-dir proc)
    (define dir (make-temporary-directory))
    (dynamic-wind void (lambda () (proc dir)) (lambda () (delete-directory/files dir))))

  ;; Runs run-study with the output root set to dir and output discarded.
  (define (study dir #:cases cases #:repetitions [r 3])
    (parameterize ([current-output-root dir]
                   [current-output-port (open-output-nowhere)])
      (run-study #:cases cases #:repetitions r)))

  ;; A case whose thunks give n (plain gives n + offset); builders make a fresh thunk.
  (define (fake-case id variant [sizes '(4 8)] #:plain-offset [offset 0])
    (bench-case id variant sizes values
                (lambda (n) (lambda () n))
                (lambda (n) (lambda () (+ n offset)))
                equal?))

  ;; A case whose thunk sleeps and gives n; (sleeps k) is the sleep in seconds of call k.
  (define (sleeping-case id sleeps)
    (define (builder n)
      (define calls 0)
      (lambda ()
        (set! calls (add1 calls))
        (sleep (sleeps calls))
        n))
    (bench-case id 'v '(4) values builder builder equal?))

  (define (raw-path dir id variant) (build-path dir (format "raw-~a-~a.rktd" id variant)))
  (define (read-datum path) (call-with-input-file path read))
  (define (raw-records dir id variant)
    (cdr (assq 'records (read-datum (raw-path dir id variant)))))
  (define (record-times r) (cdr (assq 'times r)))
  ;; Each record holds r samples, or 2r when its point was re-run after being flagged.
  (define (check-sample-counts records r)
    (for ([rec (in-list records)])
      (check-not-false (memv (length (record-times rec)) (list r (* 2 r))))))
  (define (record-batch r) (cdr (assq 'batch r)))

  ;; ------------------------------------------------------------
  ;; run-study
  ;; ------------------------------------------------------------

  (test-case "run-study: should accept #:cases and #:repetitions as optional keywords"
    (define-values (required allowed) (procedure-keywords run-study))
    (check-equal? required '())
    (check-equal? allowed '(#:cases #:repetitions)))

  (test-case "run-study: should write raw-<id>-<variant>.rktd, summary.org and environment.rktd when given one case and #:repetitions 3"
    (call-with-temp-dir
     (lambda (dir)
       (define results (study dir #:cases (list (fake-case 'a 'v))))
       (check-equal? (length results) 1)
       (check-equal? (listing dir)
                     (map path->string
                          (list dir (build-path dir "environment.rktd") (raw-path dir 'a 'v)
                                (build-path dir "summary.org"))))
       (define records (raw-records dir 'a 'v))
       (check-equal? (length records) 4)
       (check-sample-counts records 3))))

  (test-case "run-study: should write a file per case when given two cases"
    (call-with-temp-dir
     (lambda (dir)
       (study dir #:cases (list (fake-case 'a 'v) (fake-case 'b 'v)))
       (check-true (file-exists? (raw-path dir 'a 'v)))
       (check-true (file-exists? (raw-path dir 'b 'v)))
       (check-true (file-exists? (build-path dir "summary.org"))))))

  (test-case "run-study: should write only the cases it is given"
    (call-with-temp-dir
     (lambda (dir)
       (define defined (list (fake-case 'a 'v) (fake-case 'b 'v)))
       (study dir #:cases (list (car defined)))
       (check-true (file-exists? (raw-path dir 'a 'v)))
       (check-false (file-exists? (raw-path dir 'b 'v))))))

  (test-case "run-study: should write the header-only summary.org and environment.rktd and no raw file when #:cases is empty"
    (call-with-temp-dir
     (lambda (dir)
       (check-not-exn (lambda () (study dir #:cases '())))
       (check-equal? (file->string (build-path dir "summary.org")) (render-summary '()))
       (check-true (file-exists? (build-path dir "environment.rktd")))
       (check-equal? (filter (lambda (p) (regexp-match? #rx"raw-" p)) (listing dir)) '()))))

  (test-case "run-study: should use 15 repetitions when #:repetitions is omitted"
    (call-with-temp-dir
     (lambda (dir)
       (define results
         (parameterize ([current-output-root dir]
                        [current-output-port (open-output-nowhere)])
           (run-study #:cases (list (fake-case 'a 'v)))))
       (check-sample-counts (raw-records dir 'a 'v) 15))))

  (test-case "run-study: should re-run a flagged point with doubled repetitions and keep the flag"
    (call-with-temp-dir
     (lambda (dir)
       ;; Depends on sleep timing to produce a flagged point (not deterministic).
       ;; Given: the first call takes 30 ms, then 1 ms and 30 ms alternately
       (define c (sleeping-case 'a (lambda (k) (if (odd? k) 0.03 0.001))))
       ;; When
       (define results (study dir #:cases (list c)))
       ;; Then
       (check-equal? (case-result-flags (car results)) (list (cons #t #t)))
       (for ([r (in-list (raw-records dir 'a 'v))])
         (check-equal? (length (record-times r)) 6))
       (check-regexp-match #rx"flagged [|] re-run" (file->string (build-path dir "summary.org"))))))

  (test-case "run-study: should void a case whose check fails and still run the others"
    (call-with-temp-dir
     (lambda (dir)
       (define bad (fake-case 'bad 'v '(4 8) #:plain-offset 1))
       (define good (fake-case 'good 'v))
       (check-not-exn (lambda () (study dir #:cases (list bad good))))
       (check-false (file-exists? (raw-path dir 'bad 'v)))
       (check-true (file-exists? (raw-path dir 'good 'v)))
       (check-regexp-match #rx"bad v at n=4" (file->string (build-path dir "summary.org"))))))

  (test-case "run-study: should leave finished cases complete and the rest unwritten when a case raises"
    (call-with-temp-dir
     (lambda (dir)
       ;; Given
       (define raising
         (bench-case 'b 'v '(4) values
                     (lambda (n) (lambda () (error "boom")))
                     (lambda (n) (lambda () n))
                     equal?))
       ;; When / Then
       (check-exn #rx"boom"
                  (lambda () (study dir #:cases (list (fake-case 'a 'v) raising (fake-case 'c 'v)))))
       (check-true (file-exists? (raw-path dir 'a 'v)))
       (check-equal? (length (raw-records dir 'a 'v)) 4)
       (check-false (file-exists? (raw-path dir 'b 'v)))
       (check-false (file-exists? (raw-path dir 'c 'v))))))

  (test-case "run-study: should raise when #:repetitions is below 1"
    (call-with-temp-dir
     (lambda (dir)
       (for ([r (in-list '(0 -1))])
         (check-exn exn:fail? (lambda () (study dir #:cases (list (fake-case 'a 'v)) #:repetitions r))))
       (check-equal? (listing dir) (list (path->string dir))))))

  (test-case "run-study: should write nothing outside the output root"
    (call-with-temp-dir
     (lambda (dir)
       (define before (listing data-dir))
       (study dir #:cases (list (fake-case 'a 'v)))
       (check-equal? (listing data-dir) before))))

  (test-case "run-study: should record a batch factor from time-run"
    (call-with-temp-dir
     (lambda (dir)
       (study dir #:cases (list (fake-case 'a 'v)))
       (for ([r (in-list (raw-records dir 'a 'v))])
         (check-true (>= (record-batch r) 2))))))

  ;; ------------------------------------------------------------
  ;; case-by-id
  ;; ------------------------------------------------------------

  (test-case "case-by-id: should raise exn:fail when the id is unknown"
    (check-exn exn:fail? (lambda () (case-by-id "nope")))
    (check-exn exn:fail? (lambda () (case-by-id 'nope))))

  (test-case "case-by-id: should return the bench-cases of the id, as symbol or string, or all cases when no argument is given"
    (define (shape cases) (map (lambda (c) (list (bench-case-id c) (bench-case-variant c))) cases))
    (check-equal? (shape (case-by-id 'w3)) (shape (case-by-id "w3")))
    (check-equal? (shape (case-by-id 'w3)) '((w3 default)))
    (check-equal? (shape (case-by-id 'w4)) '((w4 complete) (w4 degenerate)))
    (define all (case-by-id))
    (check-equal? (remove-duplicates (map bench-case-id all))
                  '(w1 w2 w3 w4 w5 u1 u2 u3 u4 u5 u6 u7 u8 u9))
    (check-equal? (length all) 24))

  ;; ------------------------------------------------------------
  ;; Module level
  ;; ------------------------------------------------------------

  (define (require-quietly file)
    (define out (open-output-string))
    (parameterize ([current-namespace (make-base-namespace)]
                   [current-output-port out]
                   [current-error-port out])
      (dynamic-require (build-path here-dir file) #f))
    (get-output-string out))

  (test-case "requiring a benchmark module: should do nothing when required"
    (define before (listing data-dir))
    (for ([file (in-list '("case.rkt" "stats.rkt" "workloads.rkt" "micro.rkt" "handlers.rkt"
                           "measure.rkt" "environment.rkt" "report.rkt"))])
      (check-equal? (require-quietly file) "" file))
    (check-equal? (listing data-dir) before))

  (test-case "requiring run.rkt: should not start the study when required"
    (define before (listing data-dir))
    (define existed? (directory-exists? (build-path data-dir "performance-benchmark")))
    (check-equal? (require-quietly "run.rkt") "")
    (check-equal? (directory-exists? (build-path data-dir "performance-benchmark")) existed?)
    (check-equal? (listing data-dir) before)))
