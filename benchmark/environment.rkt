#lang racket/base

(provide
 current-racket-command
 current-cpuinfo-path
 current-meminfo-path
 current-loadavg-path
 current-uname-command
 current-power-dir
 record-environment)

(require
 racket/file
 racket/list
 racket/port
 racket/string
 racket/system)

(define unavailable "unavailable")

(define current-racket-command (make-parameter "racket"))
(define current-cpuinfo-path (make-parameter "/proc/cpuinfo"))
(define current-meminfo-path (make-parameter "/proc/meminfo"))
(define current-loadavg-path (make-parameter "/proc/loadavg"))
(define current-uname-command (make-parameter "uname"))
(define current-power-dir (make-parameter "/sys"))

;; An association list from symbol to string or number, every key always present.
;; Type: (-> (Listof (Pair Symbol (U String Real))))
;; Impure: runs two subprocesses and reads system files; an unreadable source gives "unavailable".
(define (record-environment)
  (define cpuinfo (read-file! (current-cpuinfo-path)))
  (define loadavg (trimmed-or-unavailable (read-file! (current-loadavg-path))))
  (list (cons 'racket-version (trimmed-or-unavailable (command-output! (current-racket-command) "--version")))
        (cons 'vm (symbol->string (system-type 'vm)))
        (cons 'cpu-model (cpu-model cpuinfo))
        (cons 'core-count (core-count cpuinfo))
        (cons 'memory (memory (read-file! (current-meminfo-path))))
        (cons 'os (trimmed-or-unavailable (command-output! (current-uname-command) "-a")))
        (cons 'load-start loadavg)
        (cons 'load-end loadavg)
        (cons 'governor (governor))
        (cons 'power-source (power-source))))

;; Type: (-> (U Path String) (U String #f))
;; Impure: reads a file; #f when it cannot be read.
(define (read-file! path)
  (with-handlers ([exn:fail? (lambda (e) #f)])
    (file->string path)))

;; Type: (-> (U Path String) String (U String #f))
;; Impure: runs a subprocess; #f when it is missing or exits with an error.
(define (command-output! command arg)
  (with-handlers ([exn:fail? (lambda (e) #f)])
    (define exe (if (absolute-path? command) command (find-executable-path command)))
    (and exe
         (let* ([out (open-output-string)]
                [ok? (parameterize ([current-output-port out]
                                    [current-error-port (open-output-nowhere)]
                                    [current-input-port (open-input-string "")])
                       (system* exe arg))])
           (and ok? (get-output-string out))))))

;; Type: (-> (U String #f) String)
(define (trimmed-or-unavailable text)
  (define trimmed (and text (string-trim text)))
  (if (and trimmed (not (string=? trimmed ""))) trimmed unavailable))

;; Type: (-> (U String #f) (U String Real))
(define (cpu-model cpuinfo)
  (define m (and cpuinfo (regexp-match #px"(?m:^model name\\s*:\\s*(.*)$)" cpuinfo)))
  (if m (string-trim (cadr m)) unavailable))

;; Type: (-> (U String #f) (U String Real))
(define (core-count cpuinfo)
  (define count (if cpuinfo (length (regexp-match* #px"(?m:^processor\\s*:)" cpuinfo)) 0))
  (if (zero? count) unavailable count))

;; Type: (-> (U String #f) String)
(define (memory meminfo)
  (define m (and meminfo (regexp-match #px"(?m:^MemTotal:\\s*(.*)$)" meminfo)))
  (if m (string-trim (cadr m)) unavailable))

;; Type: (-> String)
;; Impure: reads the cpufreq policy file below the power directory.
(define (governor)
  (define dir (current-power-dir))
  (define candidates
    (list (build-path dir "cpufreq" "policy0" "scaling_governor")
          (build-path dir "devices" "system" "cpu" "cpufreq" "policy0" "scaling_governor")))
  (or (for/first ([path (in-list candidates)]
                  #:when (read-file! path))
        (trimmed-or-unavailable (read-file! path)))
      unavailable))

;; Type: (-> String)
;; Impure: lists the power_supply directory below the power directory.
(define (power-source)
  (define dir (current-power-dir))
  (define supply
    (for/first ([path (in-list (list (build-path dir "power_supply")
                                     (build-path dir "class" "power_supply")))]
                #:when (directory-exists? path))
      path))
  (define entries
    (if supply
        (with-handlers ([exn:fail? (lambda (e) '())])
          (for/list ([name (in-list (sort (map path->string (directory-list supply)) string<?))])
            (supply-entry supply name)))
        '()))
  (if (null? entries) unavailable (string-join entries ", ")))

;; Type: (-> Path String String)
;; Impure: reads the type and online files of one power supply.
(define (supply-entry supply name)
  (define (field file)
    (define text (read-file! (build-path supply name file)))
    (and text (string-trim text)))
  (string-join (filter values (list name (field "type")
                                    (let ([online (field "online")])
                                      (and online (format "online=~a" online)))))
               ":"))

(module+ test
  (require
   rackunit
   racket/file
   racket/port)

  (define keys
    '(racket-version vm cpu-model core-count memory os load-start load-end governor power-source))

  (define (env-ref env key) (cdr (assq key env)))

  ;; Runs body with a fresh temporary directory, deleting it afterwards.
  (define (call-with-temp-dir proc)
    (define dir (make-temporary-directory))
    (dynamic-wind void (lambda () (proc dir)) (lambda () (delete-directory/files dir))))

  (define (write-fixture! path text)
    (make-parent-directory* path)
    (display-to-file text path #:exists 'truncate/replace))

  ;; Every file below dir with its contents, and every directory, sorted.
  (define (tree-snapshot dir)
    (sort (for/list ([p (in-list (find-files (lambda (_) #t) dir))])
            (list (path->string p)
                  (if (file-exists? p) (file->string p) 'directory)))
          string<? #:key car))

  (define (script! path output)
    (write-fixture! path (format "#!/bin/sh\necho \"~a\"\n" output))
    (file-or-directory-permissions path #o755))

  ;; All six sources pointing at things that do not exist.
  (define-syntax-rule (with-missing-sources dir body ...)
    (parameterize ([current-racket-command (path->string (build-path dir "no-racket"))]
                   [current-cpuinfo-path (build-path dir "no-cpuinfo")]
                   [current-meminfo-path (build-path dir "no-meminfo")]
                   [current-loadavg-path (build-path dir "no-loadavg")]
                   [current-uname-command (path->string (build-path dir "no-uname"))]
                   [current-power-dir (build-path dir "no-power")])
      body ...))

  (test-case "record-environment: should return an association list with every listed key once"
    (define env (record-environment))
    (check-equal? (sort (map car env) symbol<?) (sort keys symbol<?)))

  (test-case "record-environment: should report the racket version and the VM"
    (define expected
      (let ([exe (find-executable-path "racket")])
        (and exe
             (let ([out (open-output-string)])
               (parameterize ([current-output-port out]) (system* exe "--version"))
               (string-trim (get-output-string out))))))
    (define env (record-environment))
    (check-equal? (env-ref env 'racket-version) expected)
    (check-equal? (env-ref env 'vm) (symbol->string (system-type 'vm))))

  (test-case "record-environment: should read model and core count from a cpuinfo file"
    (call-with-temp-dir
     (lambda (dir)
       (define path (build-path dir "cpuinfo"))
       (write-fixture! path "processor : 0\nmodel name : Test CPU\n\nprocessor : 1\nmodel name : Test CPU\n")
       (define env (parameterize ([current-cpuinfo-path path]) (record-environment)))
       (check-equal? (env-ref env 'cpu-model) "Test CPU")
       (check-equal? (env-ref env 'core-count) 2))))

  (test-case "record-environment: should read memory from a meminfo file"
    (call-with-temp-dir
     (lambda (dir)
       (define path (build-path dir "meminfo"))
       (write-fixture! path "MemTotal:        2048 kB\nMemFree: 1 kB\n")
       (define env (parameterize ([current-meminfo-path path]) (record-environment)))
       (check-regexp-match #rx"2048" (env-ref env 'memory)))))

  (test-case "record-environment: should read load-start and load-end from a loadavg file"
    (call-with-temp-dir
     (lambda (dir)
       (define path (build-path dir "loadavg"))
       (write-fixture! path "0.10 0.20 0.30 1/100 999\n")
       (define env (parameterize ([current-loadavg-path path]) (record-environment)))
       (check-regexp-match #rx"0[.]10" (env-ref env 'load-start))
       (check-regexp-match #rx"0[.]10" (env-ref env 'load-end)))))

  (test-case "record-environment: should read the operating system from the uname command"
    (call-with-temp-dir
     (lambda (dir)
       (define command (build-path dir "fake-uname"))
       (script! command "TestOS 1.0")
       (define env (parameterize ([current-uname-command (path->string command)])
                     (record-environment)))
       (check-equal? (env-ref env 'os) "TestOS 1.0"))))

  (test-case "record-environment: should say unavailable when the racket command is missing"
    (call-with-temp-dir
     (lambda (dir)
       (define env (parameterize ([current-racket-command (path->string (build-path dir "no-racket"))])
                     (record-environment)))
       (check-equal? (env-ref env 'racket-version) "unavailable")
       (check-equal? (env-ref env 'vm) (symbol->string (system-type 'vm))))))

  (test-case "record-environment: should say unavailable for model and core count when the cpuinfo file is missing"
    (call-with-temp-dir
     (lambda (dir)
       (define env (parameterize ([current-cpuinfo-path (build-path dir "none")])
                     (record-environment)))
       (check-equal? (env-ref env 'cpu-model) "unavailable")
       (check-equal? (env-ref env 'core-count) "unavailable")
       (check-equal? (env-ref env 'vm) (symbol->string (system-type 'vm))))))

  (test-case "record-environment: should say unavailable for memory when the meminfo file is missing"
    (call-with-temp-dir
     (lambda (dir)
       (define env (parameterize ([current-meminfo-path (build-path dir "none")])
                     (record-environment)))
       (check-equal? (env-ref env 'memory) "unavailable"))))

  (test-case "record-environment: should say unavailable for both load entries when the loadavg file is missing"
    (call-with-temp-dir
     (lambda (dir)
       (define env (parameterize ([current-loadavg-path (build-path dir "none")])
                     (record-environment)))
       (check-equal? (env-ref env 'load-start) "unavailable")
       (check-equal? (env-ref env 'load-end) "unavailable"))))

  (test-case "record-environment: should say unavailable for the OS when the uname command is missing"
    (call-with-temp-dir
     (lambda (dir)
       (define env (parameterize ([current-uname-command (path->string (build-path dir "none"))])
                     (record-environment)))
       (check-equal? (env-ref env 'os) "unavailable"))))

  (test-case "record-environment: should say unavailable for governor and power source when the power directory is missing, and for power source alone when it has no power_supply subdirectory"
    (call-with-temp-dir
     (lambda (dir)
       ;; Given (a) a missing directory, (b) a directory with a governor and no power_supply
       (define missing (build-path dir "none"))
       (define fixture (build-path dir "fixture"))
       (write-fixture! (build-path fixture "cpufreq" "policy0" "scaling_governor") "powersave\n")
       ;; When
       (define env-a (parameterize ([current-power-dir missing]) (record-environment)))
       (define env-b (parameterize ([current-power-dir fixture]) (record-environment)))
       ;; Then
       (check-equal? (env-ref env-a 'governor) "unavailable")
       (check-equal? (env-ref env-a 'power-source) "unavailable")
       (check-equal? (env-ref env-b 'governor) "powersave")
       (check-equal? (env-ref env-b 'power-source) "unavailable"))))

  (test-case "record-environment: should say unavailable for every entry except vm when all six parameters point at missing things"
    (call-with-temp-dir
     (lambda (dir)
       (define env (with-missing-sources dir (record-environment)))
       (check-equal? (sort (map car env) symbol<?) (sort keys symbol<?))
       (for ([entry (in-list env)])
         (if (eq? (car entry) 'vm)
             (check-not-equal? (cdr entry) "unavailable")
             (check-equal? (cdr entry) "unavailable" (symbol->string (car entry))))))))

  (test-case "record-environment: should say unavailable when the cpuinfo file is empty"
    (call-with-temp-dir
     (lambda (dir)
       (define path (build-path dir "cpuinfo"))
       (write-fixture! path "")
       (define env (parameterize ([current-cpuinfo-path path]) (record-environment)))
       (check-equal? (env-ref env 'cpu-model) "unavailable")
       (check-equal? (env-ref env 'core-count) "unavailable"))))

  (test-case "record-environment: should give core count but unavailable model when cpuinfo has no \"model name\" line"
    (call-with-temp-dir
     (lambda (dir)
       (define path (build-path dir "cpuinfo"))
       (write-fixture! path "processor : 0\nprocessor : 1\nprocessor : 2\nprocessor : 3\n")
       (define env (parameterize ([current-cpuinfo-path path]) (record-environment)))
       (check-equal? (env-ref env 'core-count) 4)
       (check-equal? (env-ref env 'cpu-model) "unavailable"))))

  (test-case "record-environment: should read governor and power source from the power directory and change no file"
    (call-with-temp-dir
     (lambda (dir)
       ;; Given
       (define fixture (build-path dir "fixture"))
       (write-fixture! (build-path fixture "cpufreq" "policy0" "scaling_governor") "powersave\n")
       (make-directory* (build-path fixture "power_supply" "BAT0"))
       (define before (tree-snapshot fixture))
       ;; When
       (define env (parameterize ([current-power-dir fixture]) (record-environment)))
       ;; Then
       (check-equal? (env-ref env 'governor) "powersave")
       (check-true (string? (env-ref env 'power-source)))
       (check-not-equal? (env-ref env 'power-source) "unavailable")
       (check-equal? (tree-snapshot fixture) before))))

  (test-case "record-environment parameters: should default to racket, /proc/cpuinfo, /proc/meminfo, /proc/loadavg and uname, and hold a path for the power directory"
    (check-equal? (current-racket-command) "racket")
    (check-equal? (current-cpuinfo-path) "/proc/cpuinfo")
    (check-equal? (current-meminfo-path) "/proc/meminfo")
    (check-equal? (current-loadavg-path) "/proc/loadavg")
    (check-equal? (current-uname-command) "uname")
    (check-true (or (path? (current-power-dir)) (string? (current-power-dir)))))

  (test-case "record-environment: should return strings or numbers only"
    (for ([entry (in-list (record-environment))])
      (check-true (or (string? (cdr entry)) (number? (cdr entry)))
                  (symbol->string (car entry))))))
