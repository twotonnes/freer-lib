#lang racket/base

(provide
 (struct-out case-result)
 current-output-root
 render-summary
 write-raw
 write-summary)

(require
 racket/file
 racket/list
 racket/pretty
 racket/runtime-path
 racket/string
 "measure.rkt"
 "stats.rkt")

(define-runtime-path benchmark-dir ".")

;; id, variant: Symbol, sizes: (Listof Natural);
;; monadic and plain: per n, a (cons sample summary) where the summary is of the times;
;; flags: per n, a (cons flagged? re-run?); excluded: (Listof Natural) of sizes whose
;; median was not positive; failure: #f or (list id variant n) of a failed check.
(struct case-result (id variant sizes monadic plain flags excluded failure) #:transparent)

;; Type: parameter of Path
;; The output directory, research/data/performance-benchmark/ below the repository root.
(define current-output-root
  (make-parameter
   (path->directory-path
    (simplify-path (build-path benchmark-dir 'up "research" "data" "performance-benchmark") #f))))

(define spread-threshold 0.2)

;; ============================================================
;; Rendering (pure)
;; ============================================================

;; Type: (-> (U case-result (Listof case-result)) String)
(define (render-summary results)
  (string-append
   (render-header)
   (apply string-append (map render-case (as-list results)))))

;; Type: (-> String)
(define (render-header)
  (string-append
   "#+TITLE: Performance benchmark: summary\n\n"
   "Spread threshold: " (number->string spread-threshold)
   " (a point is flagged when its IQR exceeds this share of its median).\n"
   "Quartile method: R-7.\n"
   "Times are milliseconds per operation; the overhead ratio is monadic over plain.\n"))

;; Type: (-> case-result String)
(define (render-case r)
  (string-append
   "\n* " (symbol->string (case-result-id r)) " " (symbol->string (case-result-variant r)) "\n"
   (if (case-result-failure r)
       (render-failure (case-result-failure r))
       (string-append
        (render-version "monadic" r (case-result-monadic r))
        (render-version "plain" r (case-result-plain r))
        (render-overhead r)
        (render-slopes r)
        (render-excluded r)))))

;; Type: (-> (Listof Any) String)
(define (render-failure failure)
  (format "\nCheck failed: monadic and plain results differ for ~a ~a at n=~a. Nothing was timed.\n"
          (first failure) (second failure) (third failure)))

;; Type: (-> String case-result (Listof (Pair sample summary)) String)
(define (render-version name r points)
  (string-append
   "\n** " name "\n"
   "| n | median | min | max | iqr | bytes per op | GC share | flag | re-run |\n"
   "|---+--------+-----+-----+-----+--------------+----------+------+--------|\n"
   (apply string-append
          (for/list ([n (in-list (case-result-sizes r))]
                     [point (in-list points)]
                     [flag (in-list (case-result-flags r))])
            (render-row n point flag)))))

;; Type: (-> Natural (Pair sample summary) (Pair Boolean Boolean) String)
(define (render-row n point flag)
  (define s (car point))
  (define t (cdr point))
  (define ops (sample-ops s))
  (string-append
   "| " (string-join
         (list (number->string n)
               (fmt (/ (summary-median t) ops))
               (fmt (/ (summary-min t) ops))
               (fmt (/ (summary-max t) ops))
               (fmt (/ (summary-iqr t) ops))
               (fmt (/ (median-of (sample-bytes s)) ops))
               (gc-share s)
               (if (car flag) "flagged" "-")
               (if (cdr flag) "re-run" "-"))
         " | ")
   " |\n"))

;; Type: (-> sample String)
(define (gc-share s)
  (define time (median-of (sample-times s)))
  (if (> time 0)
      (fmt (/ (median-of (sample-gcs s)) time))
      "n/a"))

;; Type: (-> (Listof Real) Real)
(define (median-of values)
  (summary-median (summarise values)))

;; Type: (-> case-result String)
(define (render-overhead r)
  (string-append
   "\n** overhead ratio\n"
   "| n | monadic over plain |\n"
   "|---+--------------------|\n"
   (apply string-append
          (for/list ([n (in-list (case-result-sizes r))]
                     [m (in-list (case-result-monadic r))]
                     [p (in-list (case-result-plain r))])
            (define plain-time (per-op p))
            (format "| ~a | ~a |\n" n
                    (if (> plain-time 0) (fmt-decimal (/ (per-op m) plain-time)) "n/a"))))))

;; Type: (-> (Pair sample summary) Real)
(define (per-op point)
  (/ (summary-median (cdr point)) (sample-ops (car point))))

;; Type: (-> case-result String)
(define (render-slopes r)
  (define sizes (case-result-sizes r))
  (define upper (drop sizes (quotient (length sizes) 2)))
  (string-append
   "\n** scaling exponent (log-log slope of time per run against n)\n"
   "| version | fit | range | slope |\n"
   "|---------+-----+-------+-------|\n"
   (slope-row "monadic" "whole series" sizes (case-result-monadic r) #f)
   (slope-row "monadic" "upper half" sizes (case-result-monadic r) upper)
   (slope-row "plain" "whole series" sizes (case-result-plain r) #f)
   (slope-row "plain" "upper half" sizes (case-result-plain r) upper)))

;; Type: (-> String String (Listof Natural) (Listof (Pair sample summary)) (U (Listof Natural) #f) String)
(define (slope-row version fit-name sizes points restrict)
  (define-values (kept excluded)
    (split-positive
     (for/list ([n (in-list sizes)] [p (in-list points)])
       (cons n (/ (summary-median (cdr p)) (sample-batch (car p)))))))
  (define range (and restrict (pair? restrict) (cons (first restrict) (last restrict))))
  (define fitted
    (filter (lambda (p) (or (not restrict) (and range (<= (car range) (car p) (cdr range))))) kept))
  (define shown-range
    (cond [range range]
          [(pair? sizes) (cons (first sizes) (last sizes))]
          [else #f]))
  (format "| ~a | ~a | ~a | ~a |\n" version fit-name
          (if shown-range (format "~a to ~a" (car shown-range) (cdr shown-range)) "n/a")
          (if (< (length fitted) 2)
              "n/a"
              (fmt (fit-slope (log-log-slope (map car fitted) (map cdr fitted)
                                             #:range range))))))

;; Type: (-> case-result String)
(define (render-excluded r)
  (if (null? (case-result-excluded r))
      ""
      (format "\nExcluded from the fits (median not positive): n = ~a\n"
              (string-join (map number->string (case-result-excluded r)) ", "))))

;; Exact integers print as they are; other reals with six decimals.
;; Type: (-> Real String)
(define (fmt x)
  (if (exact-integer? x)
      (number->string x)
      (fmt-decimal x)))

;; Type: (-> Real String)
(define (fmt-decimal x)
  (real->decimal-string (exact->inexact x) 6))

;; Type: (-> (U case-result (Listof case-result)) (Listof case-result))
(define (as-list results)
  (if (case-result? results) (list results) results))

;; ============================================================
;; Files (impure)
;; ============================================================

;; Type: (-> (U case-result (Listof case-result)) (Listof Any) Void)
;; Impure: writes raw-<id>-<variant>.rktd below current-output-root, creating the directory.
;; Raises exn:fail:filesystem when the root cannot be created or written.
(define (write-raw results environment)
  (for ([r (in-list (as-list results))])
    (write-datum! (format "raw-~a-~a.rktd" (case-result-id r) (case-result-variant r))
                  (raw-datum r environment))))

;; Type: (-> case-result (Listof Any) (Listof Any))
(define (raw-datum r environment)
  (list (cons 'id (case-result-id r))
        (cons 'variant (case-result-variant r))
        (cons 'environment environment)
        (cons 'records
              (append (raw-records 'monadic (case-result-sizes r) (case-result-monadic r))
                      (raw-records 'plain (case-result-sizes r) (case-result-plain r))))))

;; Type: (-> Symbol (Listof Natural) (Listof (Pair sample summary)) (Listof Any))
(define (raw-records version sizes points)
  (for/list ([n (in-list sizes)] [point (in-list points)])
    (define s (car point))
    (list (cons 'version version)
          (cons 'n n)
          (cons 'times (sample-times s))
          (cons 'bytes (sample-bytes s))
          (cons 'gc-ms (sample-gcs s))
          (cons 'ops (sample-ops s))
          (cons 'batch (sample-batch s)))))

;; Type: (-> (U case-result (Listof case-result)) (Listof Any) Void)
;; Impure: writes summary.org and environment.rktd below current-output-root, creating the directory.
;; Raises exn:fail:filesystem when the root cannot be created or written.
(define (write-summary results environment)
  (define root (current-output-root))
  (make-directory* root)
  (call-with-output-file (build-path root "summary.org") #:exists 'truncate/replace
    (lambda (out) (write-string (render-summary results) out)))
  (write-datum! "environment.rktd" environment))

;; Type: (-> String Any Void)
;; Impure: writes one readable datum to a file below current-output-root.
(define (write-datum! file-name datum)
  (define root (current-output-root))
  (make-directory* root)
  (call-with-output-file (build-path root file-name) #:exists 'truncate/replace
    (lambda (out)
      (pretty-write datum out))))

(module+ test
  (require
   rackunit
   racket/file)

  ;; A point from per-run times with ops 1 and batch 1.
  (define (point times #:bytes [bytes '(0)] #:gcs [gcs '(0)] #:ops [ops 1])
    (cons (sample times bytes gcs ops 1) (summarise times)))

  ;; A result with sizes (64 128), monadic medians 20 and 30, plain 10 and 10.
  (define (fixture #:id [id 'w9] #:variant [variant 'left]
                   #:monadic [monadic (list (point '(20)) (point '(30)))]
                   #:plain [plain (list (point '(10)) (point '(10)))]
                   #:flags [flags (list (cons #f #f) (cons #f #f))]
                   #:excluded [excluded '()]
                   #:failure [failure #f])
    (case-result id variant '(64 128) monadic plain flags excluded failure))

  (define environment '((racket-version . "9.3") (vm . "chez-scheme") (core-count . 4)))

  (define (call-with-temp-dir proc)
    (define dir (make-temporary-directory))
    (dynamic-wind void (lambda () (proc dir)) (lambda () (delete-directory/files dir))))

  ;; Every path below dir, sorted; '() when dir does not exist.
  (define (listing dir)
    (if (directory-exists? dir)
        (sort (map path->string (find-files (lambda (_) #t) dir)) string<?)
        '()))

  (define data-dir (simplify-path (build-path benchmark-dir 'up "research" "data")))

  (define (lines text) (regexp-split #rx"\n" text))

  ;; ------------------------------------------------------------
  ;; render-summary
  ;; ------------------------------------------------------------

  (test-case "render-summary: should return a string"
    (check-true (string? (render-summary (fixture)))))

  (test-case "render-summary: should show the case id and variant"
    (define text (render-summary (fixture)))
    (check-regexp-match #rx"w9" text)
    (check-regexp-match #rx"left" text))

  (test-case "render-summary: should show the overhead ratio at each n"
    (define text (render-summary (fixture)))
    (check-regexp-match #rx"[|] 64 [|] 2[.]000000 [|]" text)
    (check-regexp-match #rx"[|] 128 [|] 3[.]000000 [|]" text))

  (test-case "render-summary: should show median, min, max and iqr for both versions at each n"
    ;; Given
    (define monadic (list (point '(11 21 33 41 52)) (point '(101 102 103 104 105))))
    (define plain (list (point '(5 6 7 8 9)) (point '(201 205 207 209 211))))
    ;; When
    (define text (render-summary (fixture #:monadic monadic #:plain plain)))
    ;; Then
    (define (row prefix) (filter (lambda (l) (regexp-match? prefix l)) (lines text)))
    (define monadic-64 (car (row #rx"^[|] 64 [|] 33 ")))
    (check-regexp-match #rx"[|] 64 [|] 33 [|] 11 [|] 52 [|] 20 [|]" monadic-64)
    (check-regexp-match #rx"[|] 64 [|] 7 [|] 5 [|] 9 [|] 2 [|]" text)
    (check-regexp-match #rx"[|] 128 [|] 103 [|] 101 [|] 105 [|] 2 [|]" text)
    (check-regexp-match #rx"[|] 128 [|] 207 [|] 201 [|] 211 [|] 4 [|]" text))

  (test-case "render-summary: should show bytes per operation and GC share"
    ;; Given
    (define monadic (list (point '(10) #:bytes '(4000) #:gcs '(2) #:ops 100) (point '(30))))
    ;; When
    (define text (render-summary (fixture #:monadic monadic)))
    ;; Then
    (check-regexp-match #rx"[|] 64 [|] [^|]*[|] [^|]*[|] [^|]*[|] [^|]*[|] 40 [|] 0[.]200000 [|]" text))

  (test-case "render-summary: should mark a flagged point only and show whether it was re-run"
    ;; Given
    (define flags (list (cons #t #t) (cons #f #f)))
    ;; When
    (define text (render-summary (fixture #:flags flags)))
    ;; Then
    (define rows-64 (filter (lambda (l) (regexp-match? #rx"^[|] 64 [|].*[|] [-a-z]+ [|] [-a-z]+ [|]$" l))
                            (lines text)))
    (define rows-128 (filter (lambda (l) (regexp-match? #rx"^[|] 128 [|].*[|] [-a-z]+ [|] [-a-z]+ [|]$" l))
                             (lines text)))
    (check-equal? (length rows-64) 2)
    (check-equal? (length rows-128) 2)
    (for ([l (in-list rows-64)]) (check-regexp-match #rx"flagged [|] re-run [|]$" l))
    (for ([l (in-list rows-128)]) (check-regexp-match #rx"- [|] - [|]$" l)))

  (test-case "render-summary: should show slope with range for monadic and plain, whole series and upper half"
    ;; Given
    (define sizes '(64 128 256 512))
    (define (points medians) (for/list ([m (in-list medians)]) (point (list m))))
    (define result
      (case-result 'w9 'left sizes (points '(64 128 256 512)) (points '(1 2 8 32))
                   (for/list ([n (in-list sizes)]) (cons #f #f)) '() #f))
    ;; When
    (define text (render-summary result))
    ;; Then
    (check-regexp-match #rx"[|] monadic [|] whole series [|] 64 to 512 [|] 1[.]000000 [|]" text)
    (check-regexp-match #rx"[|] monadic [|] upper half [|] 256 to 512 [|] 1[.]000000 [|]" text)
    (check-regexp-match #rx"[|] plain [|] whole series [|] 64 to 512 [|] 1[.]700000 [|]" text)
    (check-regexp-match #rx"[|] plain [|] upper half [|] 256 to 512 [|] 2[.]000000 [|]" text))

  (test-case "render-summary: should list excluded points and not raise when a median is not positive"
    ;; Given
    (define plain (list (point '(0)) (point '(10))))
    (define result (fixture #:plain plain #:excluded '(64)))
    ;; When
    (define text (render-summary result))
    ;; Then
    (check-regexp-match #rx"Excluded[^\n]*n = 64" text))

  (test-case "render-summary: should show a failed case-check naming id, variant and n"
    (define result
      (case-result 'w9 'left '() '() '() '() '() (list 'w9 'left 8)))
    (define text (render-summary result))
    (check-regexp-match #rx"Check failed[^\n]*w9 left at n=8" text))

  (test-case "render-summary: should return a string without cases when given the empty list"
    (define text (render-summary '()))
    (check-true (string? text))
    (check-false (regexp-match? #rx"^[*] " text)))

  (test-case "render-summary: should keep the order of the cases"
    (define text (render-summary (list (fixture #:id 'aaa) (fixture #:id 'bbb))))
    (define a (caar (regexp-match-positions #rx"aaa" text)))
    (define b (caar (regexp-match-positions #rx"bbb" text)))
    (check-true (< a b)))

  (test-case "render-summary: should be pure and give equal strings when called twice"
    (call-with-temp-dir
     (lambda (dir)
       (define root (build-path dir "absent"))
       (parameterize ([current-output-root root])
         (define first-text (render-summary (fixture)))
         (define second-text (render-summary (fixture)))
         (check-equal? first-text second-text)
         (check-false (directory-exists? root))
         (check-equal? (listing dir) (list (path->string dir)))))))

  (test-case "render-summary: should state the spread threshold and quartile method"
    (define text (render-summary (fixture)))
    (check-regexp-match #rx"0[.]2" text)
    (check-regexp-match #rx"R-7" text))

  ;; ------------------------------------------------------------
  ;; current-output-root
  ;; ------------------------------------------------------------

  (test-case "current-output-root: should default to the absolute research/data/performance-benchmark/ path"
    (define root (current-output-root))
    (check-true (absolute-path? root))
    (check-regexp-match #rx"research/data/performance-benchmark/$" (path->string root)))

  (test-case "current-output-root: should not depend on the working directory"
    (call-with-temp-dir
     (lambda (dir)
       (define default (current-output-root))
       (parameterize ([current-directory dir])
         (check-equal? (current-output-root) default)))))

  (test-case "current-output-root: should hold the given value inside parameterize and restore the default after"
    (call-with-temp-dir
     (lambda (dir)
       (define default (current-output-root))
       (parameterize ([current-output-root dir])
         (check-equal? (current-output-root) dir))
       (check-equal? (current-output-root) default))))

  ;; ------------------------------------------------------------
  ;; write-raw
  ;; ------------------------------------------------------------

  (define (read-datum path) (call-with-input-file path read))

  (test-case "write-raw: should write raw-w9-left.rktd with one readable record per version and n"
    (call-with-temp-dir
     (lambda (dir)
       ;; Given
       (define monadic (list (point '(20 21 22) #:ops 5) (point '(30 31 32))))
       ;; When
       (parameterize ([current-output-root dir])
         (write-raw (fixture #:monadic monadic) environment))
       ;; Then
       (define datum (read-datum (build-path dir "raw-w9-left.rktd")))
       (define records (cdr (assq 'records datum)))
       (check-equal? (length records) 4)
       (check-equal? (map (lambda (r) (cons (cdr (assq 'version r)) (cdr (assq 'n r)))) records)
                     '((monadic . 64) (monadic . 128) (plain . 64) (plain . 128)))
       (check-equal? (cdr (assq 'times (car records))) '(20 21 22))
       (check-equal? (cdr (assq 'ops (car records))) 5)
       (check-equal? (cdr (assq 'batch (car records))) 1))))

  (test-case "write-raw: should store the environment in the file"
    (call-with-temp-dir
     (lambda (dir)
       (parameterize ([current-output-root dir])
         (write-raw (fixture) environment))
       (define datum (read-datum (build-path dir "raw-w9-left.rktd")))
       (check-equal? (cdr (assq 'environment datum)) environment))))

  (test-case "write-raw: should create the root and its parents when missing"
    (call-with-temp-dir
     (lambda (dir)
       (define root (build-path dir "one" "two"))
       (parameterize ([current-output-root root])
         (write-raw (fixture) environment))
       (check-true (file-exists? (build-path root "raw-w9-left.rktd"))))))

  (test-case "write-raw: should write only the one file below the root"
    (call-with-temp-dir
     (lambda (dir)
       (define before (listing data-dir))
       (parameterize ([current-output-root dir])
         (write-raw (fixture) environment))
       (check-equal? (listing dir)
                     (list (path->string dir)
                           (path->string (build-path dir "raw-w9-left.rktd"))))
       (check-equal? (listing data-dir) before))))

  (test-case "write-raw: should write one file per variant"
    (call-with-temp-dir
     (lambda (dir)
       (parameterize ([current-output-root dir])
         (write-raw (fixture #:variant 'left) environment)
         (write-raw (fixture #:variant 'right) environment))
       (check-true (file-exists? (build-path dir "raw-w9-left.rktd")))
       (check-true (file-exists? (build-path dir "raw-w9-right.rktd"))))))

  (test-case "write-raw: should replace the file when the case is written again"
    (call-with-temp-dir
     (lambda (dir)
       (parameterize ([current-output-root dir])
         (write-raw (fixture) environment)
         (write-raw (fixture #:monadic (list (point '(777)) (point '(888)))) '((vm . "second"))))
       (define text (file->string (build-path dir "raw-w9-left.rktd")))
       (check-regexp-match #rx"777" text)
       (check-false (regexp-match? #rx"chez-scheme" text))
       (check-equal? (cdr (assq 'environment (read-datum (build-path dir "raw-w9-left.rktd"))))
                     '((vm . "second"))))))

  (test-case "write-raw: should raise a filesystem error when the root is a regular file"
    (call-with-temp-dir
     (lambda (dir)
       (define root (build-path dir "afile"))
       (display-to-file "x" root)
       (parameterize ([current-output-root root])
         (check-exn exn:fail:filesystem? (lambda () (write-raw (fixture) environment)))))))

  ;; ------------------------------------------------------------
  ;; write-summary
  ;; ------------------------------------------------------------

  (test-case "write-summary: should write summary.org equal to render-summary of the same results"
    (call-with-temp-dir
     (lambda (dir)
       (define results (list (fixture) (fixture #:variant 'right)))
       (parameterize ([current-output-root dir])
         (write-summary results environment))
       (check-equal? (file->string (build-path dir "summary.org")) (render-summary results)))))

  (test-case "write-summary: should write environment.rktd as a readable alist"
    (call-with-temp-dir
     (lambda (dir)
       (parameterize ([current-output-root dir])
         (write-summary (list (fixture)) environment))
       (check-equal? (read-datum (build-path dir "environment.rktd")) environment))))

  (test-case "write-summary: should create the root and write only summary.org and environment.rktd"
    (call-with-temp-dir
     (lambda (dir)
       (define root (build-path dir "missing" "root"))
       (define before (listing data-dir))
       (parameterize ([current-output-root root])
         (write-summary (list (fixture)) environment))
       (check-equal? (listing root)
                     (map path->string
                          (list root (build-path root "environment.rktd") (build-path root "summary.org"))))
       (check-equal? (listing data-dir) before))))

  (test-case "write-summary: should write a summary file when the results list is empty"
    (call-with-temp-dir
     (lambda (dir)
       (parameterize ([current-output-root dir])
         (write-summary '() environment))
       (check-equal? (file->string (build-path dir "summary.org")) (render-summary '())))))

  (test-case "write-summary: should raise a filesystem error when the root is a regular file"
    (call-with-temp-dir
     (lambda (dir)
       (define root (build-path dir "afile"))
       (display-to-file "x" root)
       (parameterize ([current-output-root root])
         (check-exn exn:fail:filesystem? (lambda () (write-summary (list (fixture)) environment))))))))
