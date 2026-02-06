#lang racket/base

(provide
    log-effect
    log-debug
    log-info
    log-error
    default-log-display
    default-log-format)

(require
    freer-lib)

(struct log-effect (level message) #:transparent)

(define/contract (log level message)
    (-> symbol? string? free?)
    (perform (log-effect level message)))

(define/contract (log-debug message)
    (-> string? free?)
    (log 'DEBUG message))

(define/contract (log-info message)
    (-> string? free?)
    (log 'INFO message))

(define/contract (log-error message)
    (-> string? free?)
    (log 'ERROR message))

(define/contract (write-log eff [display-proc default-display] [format-proc default-format])
    (-> (log-effect?)
        ((-> log-effect? void?) (-> log-effect? string?))
        free?)
    (with-handlers ([exn:fail? (lambda (exn) (fail (format "error handling log effect: ~s" (exn-message exn))))])
        (return (display-proc eff (format-proc eff)))))

(define/contract (default-log-display eff)
    (-> log-effect? void?)
    (match (log-effect-level eff)
        ['ERROR (displayln (log-effect-message eff) (current-error-port))]
        [_ (displayln (log-effect-message eff) (current-output-port))]))

(define/contract (default-log-format eff)
    (-> log-effect? string?)
    (format ("~a ~a :: ~a"
             (current-date)
             (log-effect-level eff)
             (log-effect-message eff))))