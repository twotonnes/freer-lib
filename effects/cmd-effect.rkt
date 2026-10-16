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
        (process* (find-shell-path) (shell-flag) value))

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

;; Type: (-> Boolean)
(define (windows?)
  (eq? (system-type 'os) 'windows))

;; Type: (-> String)
;; The shell that runs a command: PowerShell on Windows, sh elsewhere.
(define (shell-name)
  (if (windows?) "powershell.exe" "sh"))

;; Type: (-> String)
;; The argument that makes the shell run the command string that follows it.
(define (shell-flag)
  (if (windows?) "-Command" "-c"))

(define/contract (find-shell-path)
  (-> path?)
  (define shell-path (find-executable-path (shell-name)))
  (if (false? shell-path)
      (error (format "could not find ~a in PATH" (shell-name)))
      shell-path))

(module+ test
  (require
    rackunit
    racket/match
    "../freer-monad.rkt")

  (test-case "cmd: should perform a cmd-effect with the command"
    (check-match (cmd "echo hi") (impure (cmd-effect "echo hi") _)))

  (test-case "find-shell-path: should return a path to an existing shell"
    (check-true (file-exists? (find-shell-path))))

  (test-case "shell-name: should be sh when not running on Windows"
    (unless (windows?)
      (check-equal? (shell-name) "sh")
      (check-equal? (shell-flag) "-c")))

  (test-case "execute-command: should return the output and exit code 0 for a successful command"
    ;; Given
    (define command "echo hello")

    ;; When
    (define result (execute-command command))

    ;; Then
    (check-equal? result (cmd-result "hello\n" "" 0)))

  (test-case "execute-command: should return stderr and the exit code of a failing command"
    ;; Given
    (define command "echo oops 1>&2; exit 3")

    ;; When
    (define result (execute-command command))

    ;; Then
    (check-equal? result (cmd-result "" "oops\n" 3)))

  (test-case "execute-command: should pass the command to the shell without changing its quoting"
    ;; Given
    (define command "printf '%s' 'a b'")

    ;; When
    (define result (execute-command command))

    ;; Then
    (check-equal? (cmd-result-out result) "a b"))

  (test-case "cmd: should run the command through a handler that calls execute-command"
    ;; Given
    (define computation (cmd "echo hi"))

    ;; When
    (define result
      (run computation
           (lambda (eff k)
             (match eff
               [(cmd-effect value) (k (execute-command value))]))))

    ;; Then
    (check-equal? result (cmd-result "hi\n" "" 0))))
