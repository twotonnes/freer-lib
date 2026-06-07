#lang racket/base

(provide
  (struct-out cmd-effect)
  (struct-out cmd-result)
  cmd
  execute-command)

(require
  racket/bool
  racket/match
  racket/port
  racket/system
  racket/exn
  racket/contract
  "../freer-monad.rkt")

(struct cmd-effect (value) #:transparent)

(struct cmd-result (out err exit-code) #:transparent)

(define/contract (cmd value)
  (-> any/c free?)
  (perform (cmd-effect value)))

(define/contract (execute-command value)
  (-> string? cmd-result?)
  (with-handlers ([exn:fail? (lambda (e) (error (format "error running system command '~a': ~a" value (exn->string e))))])
      (match-define (list stdout stdin _ stderr control)
        (process* (find-cmd-path) "-Command" value))

      (define out (port->string stdout))
      (define err (port->string stderr))

      (close-input-port stdout)
      (close-input-port stderr)
      (close-output-port stdin)

      (control 'wait)
      (define exit-code (control 'exit-code))

      (if (false? exit-code)
          (error "command returned #f as exit code")
          (cmd-result out err exit-code))))

(define/contract (find-cmd-path)
  (-> path?)
  (define cmd-name "powershell.exe")
  (define cmd-path (find-executable-path cmd-name))
  (if (false? cmd-path)
      (error (format "could not find ~a in PATH" cmd-name))
      cmd-path))