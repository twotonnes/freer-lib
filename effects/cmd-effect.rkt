#lang typed/racket

(provide
  (struct-out cmd-effect)
  (struct-out cmd-result)
  cmd
  execute-command)

(require
  "../eff-monad.rkt"
  "nothing-effect.rkt")

(struct cmd-effect effect-desc ([value : String]) #:transparent)

(struct cmd-result ([out : String]
                    [err : String]
                    [exit-code : Byte]) #:transparent)

(: cmd (-> String (Eff Any)))
(define (cmd value)
  (effect (cmd-effect value) (inst return Any)))

(: execute-command (-> String (Eff Any)))
(define (execute-command value)
    (with-handlers ([exn:fail? (lambda (e)
                                (begin
                                  (displayln (format "error running system command '~a': ~a" value e))
                                  (nothing)))])
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
            (return (cmd-result out err exit-code)))))

(: find-cmd-path (-> Path-String))
(define (find-cmd-path)
  (define cmd-name "powershell.exe")
  (define cmd-path (find-executable-path cmd-name))
  (if (false? cmd-path)
      (error (format "could not find ~a in PATH" cmd-name))
      cmd-path))