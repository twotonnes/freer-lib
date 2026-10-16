#lang racket/base


(provide
    (struct-out read-file-effect)
    (struct-out write-file-effect)
    (struct-out create-folder-effect)
    (struct-out check-path-effect)
    (struct-out delete-path-effect)
    read-file
    write-file
    create-folder
    check-path
    delete-path
    do-read-file
    do-write-file
    do-create-folder
    do-check-path
    do-delete-path)

(require
    racket/format
    racket/file
    racket/exn
    "../freer-monad.rkt")

(struct read-file-effect (path) #:transparent)
(struct write-file-effect (path bytes exists-flag) #:transparent)
(struct create-folder-effect (path) #:transparent)
(struct check-path-effect (path) #:transparent)
(struct delete-path-effect (path) #:transparent)

;; Type: (-> (U String Path) Free)
(define (read-file path)
    (perform (read-file-effect path)))

;; Type: (-> (U String Path) Bytes (U 'error 'append 'update 'replace 'truncate 'truncate/replace) Free)
(define (write-file path bytes exists-flag)
    (perform (write-file-effect path bytes exists-flag)))

;; Type: (-> (U String Path) Free)
(define (create-folder path)
    (perform (create-folder-effect path)))

;; Type: (-> (U String Path) Free)
(define (check-path path)
    (perform (check-path-effect path)))

;; Type: (-> (U String Path) Free)
(define (delete-path path)
    (perform (delete-path-effect path)))

;; Type: (-> (U String Path) Bytes)
(define (do-read-file path)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error reading file at '~a': ~a" path (exn->string exn))))])
        (file->bytes path)))

;; Type: (-> (U String Path) Bytes (U 'error 'append 'update 'replace 'truncate 'truncate/replace) Void)
(define (do-write-file path bytes exists-flag)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error writing file at '~a': ~a" path (exn->string exn))))])
        (void (call-with-output-file path #:exists exists-flag (lambda (out) (write-bytes bytes out))))))

;; Type: (-> (U String Path) Void)
(define (do-create-folder path)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error creating folder at '~a': ~a" path (exn->string exn))))])
        (make-directory* path)))

;; Type: (-> (U String Path) (U 'file 'directory 'link 'directory-link #f))
(define (do-check-path path)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error checking path at '~a': ~a" path (exn->string exn))))])
        (file-or-directory-type path)))

;; Type: (-> (U String Path) Void)
(define (do-delete-path path)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error deleting path at '~a': ~a" path (exn->string exn))))])
        (delete-directory/files path #:must-exist? #f)))

(module+ test
  (require
    rackunit
    racket/file)

  (define-syntax-rule (with-temp-dir dir body ...)
    (let ([dir (make-temporary-directory)])
      (dynamic-wind
       void
       (lambda () body ...)
       (lambda () (delete-directory/files dir)))))

  (test-case "do-write-file and do-read-file: should round-trip the bytes"
    (with-temp-dir dir
      (define p (build-path dir "a.txt"))
      (do-write-file p #"hi" 'error)
      (check-equal? (do-read-file p) #"hi")))

  (test-case "do-write-file: should raise an error when the file exists and the flag is 'error"
    (with-temp-dir dir
      (define p (build-path dir "a.txt"))
      (do-write-file p #"first" 'error)
      (check-exn exn:fail? (lambda () (do-write-file p #"second" 'error)))))

  (test-case "do-write-file: should append the bytes when the flag is 'append"
    (with-temp-dir dir
      (define p (build-path dir "a.txt"))
      (do-write-file p #"a" 'error)
      (do-write-file p #"b" 'append)
      (check-equal? (do-read-file p) #"ab")))

  (test-case "do-write-file: should raise an error when the exists flag is not a valid mode"
    (with-temp-dir dir
      (check-exn exn:fail? (lambda () (do-write-file (build-path dir "a.txt") #"x" 'bogus)))))

  (test-case "do-read-file: should raise an error when the file does not exist"
    (with-temp-dir dir
      (check-exn exn:fail? (lambda () (do-read-file (build-path dir "missing.txt"))))))

  (test-case "do-create-folder: should create nested folders"
    (with-temp-dir dir
      (define p (build-path dir "x" "y"))
      (do-create-folder p)
      (check-equal? (do-check-path p) 'directory)))

  (test-case "do-create-folder: should not raise an error when the folder already exists"
    (with-temp-dir dir
      (do-create-folder dir)
      (check-equal? (do-check-path dir) 'directory)))

  (test-case "do-check-path: should return 'file for a file and #f for a missing path"
    (with-temp-dir dir
      (define p (build-path dir "a.txt"))
      (do-write-file p #"x" 'error)
      (check-equal? (do-check-path p) 'file)
      (check-false (do-check-path (build-path dir "missing")))))

  (test-case "do-delete-path: should delete a folder and its contents"
    (with-temp-dir dir
      (define sub (build-path dir "sub"))
      (do-create-folder sub)
      (do-write-file (build-path sub "a.txt") #"x" 'error)
      (do-delete-path sub)
      (check-false (do-check-path sub))))

  (test-case "do-delete-path: should not raise an error when the path does not exist"
    (with-temp-dir dir
      (do-delete-path (build-path dir "missing"))
      (check-true #t))))
