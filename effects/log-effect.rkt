#lang racket/base


(provide
    (struct-out log-effect)
    log-dbg
    log-inf
    log-err
    write-log)


(require
    racket/contract
    racket/format
    racket/match
    racket/date
    gregor
    "../freer-monad.rkt")


(struct log-effect (level message) #:transparent)

(define/contract (log level message . args)
    (->* (symbol? string?) () #:rest list? free?)
    (define formatted-message
        (if (null? args)
            message
            (apply format message args)))
    (perform (log-effect level formatted-message)))


(define/contract (log-dbg message . args)
    (->* (string?) () #:rest list? free?)
    (apply log 'DEBUG message args))


(define/contract (log-inf message . args)
    (->* (string?) () #:rest list? free?)
    (apply log 'INFO message args))


(define/contract (log-err message . args)
    (->* (string?) () #:rest list? free?)
    (apply log 'ERROR message args))


(define/contract (write-log eff [display-proc default-log-display])
    (->* (log-effect?)
         ((-> log-effect? void?))
         void?)
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error handling log effect: ~s" (exn-message exn))))])
        (display-proc eff)))

(define/contract (default-log-display eff)
    (-> log-effect? void?)
    (define formatted (format "[~a] ~a :: ~a"
                              (moment->iso8601 (now/moment/utc))
                              (log-effect-level eff)
                              (log-effect-message eff)))
    (match (log-effect-level eff)
        ['ERROR 
         (displayln formatted (current-error-port))
         (flush-output (current-error-port))]
        [_ 
         (displayln formatted (current-output-port))
         (flush-output)]))