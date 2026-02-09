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
    racket/contract
    racket/format
    racket/file
    racket/exn
    "../freer-monad.rkt")

(struct read-file-effect (path) #:transparent)
(struct write-file-effect (path bytes exists-flag) #:transparent)
(struct create-folder-effect (path) #:transparent)
(struct check-path-effect (path) #:transparent)
(struct delete-path-effect (path) #:transparent)

(define/contract (read-file path)
    (-> path-string? free?)
    (perform (read-file-effect path)))

(define/contract (write-file path bytes exists-flag)
    (-> path-string? bytes? (or/c 'error 'append 'update 'replace 'truncate 'truncate/replace) free?)
    (perform (write-file-effect path bytes exists-flag)))

(define/contract (create-folder path)
    (-> path-string? free?)
    (perform (create-folder-effect path)))

(define/contract (check-path path)
    (-> path-string? free?)
    (perform (check-path-effect path)))

(define/contract (delete-path path)
    (-> path-string? free?)
    (perform (delete-path-effect path)))

(define/contract (do-read-file path)
    (-> path-string? bytes?)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error reading file at '~a': ~a" path (exn->string exn))))])
        (file->bytes path)))

(define/contract (do-write-file path bytes exists-flag)
    (-> path-string? bytes? (or/c 'error 'append 'update 'replace 'truncate 'truncate/replace) void?)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error writing file at '~a': ~a" path (exn->string exn))))])
        (write-to-file bytes path #:exists-flag exists-flag)))

(define/contract (do-create-folder path)
    (-> path-string? void?)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error creating folder at '~a': ~a" path (exn->string exn))))])
        (make-directory* path)))

(define/contract (do-check-path path)
    (-> path-string? (or/c 'file 'directory 'link 'directory-link #f))
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error checking path at '~a': ~a" path (exn->string exn))))])
        (file-or-directory-type path)))

(define/contract (do-delete-path path)
    (-> path-string? void?)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error deleting path at '~a': ~a" path (exn->string exn))))])
        (delete-directory/files path #:must-exist? #f)))