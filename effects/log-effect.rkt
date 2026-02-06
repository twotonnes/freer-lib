#lang racket/base


(provide
    log-effect
    log-debug
    log-info
    log-error
    write-log
    default-log-display
    default-log-format)


(require
    racket/contract
    racket/format
    racket/match
    racket/date
    "../freer-monad.rkt"
    "fail-effect.rkt")


(struct log-effect (level message) #:transparent)


(define/contract (log level message . args)
    (->* (symbol? string?) () #:rest list? free?)
    (define formatted-message
        (if (null? args)
            message
            (apply format message args)))
    (perform (log-effect level formatted-message)))


(define/contract (log-debug message . args)
    (->* (string?) () #:rest list? free?)
    (apply log 'DEBUG message args))


(define/contract (log-info message . args)
    (->* (string?) () #:rest list? free?)
    (apply log 'INFO message args))


(define/contract (log-error message . args)
    (->* (string?) () #:rest list? free?)
    (apply log 'ERROR message args))


(define/contract (write-log eff [display-proc default-log-display] [format-proc default-log-format])
    (->* (log-effect?)
         ((-> log-effect? void?) (-> log-effect? string?))
         free?)
    (with-handlers ([exn:fail? (lambda (exn) (fail (format "error handling log effect: ~s" (exn-message exn))))])
        (return (display-proc eff))))


(define/contract (default-log-display eff)
    (-> log-effect? void?)
    (define formatted (default-log-format eff))
    (match (log-effect-level eff)
        ['ERROR 
         (displayln formatted (current-error-port))
         (flush-output (current-error-port))]
        [_ 
         (displayln formatted (current-output-port))
         (flush-output)]))


(define/contract (default-log-format eff)
    (-> log-effect? string?)
    (format "~a ~a :: ~a"
            (date->string (current-date) #t)
            (log-effect-level eff)
            (log-effect-message eff)))
