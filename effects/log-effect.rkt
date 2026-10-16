#lang racket/base


(provide
    (struct-out log-effect)
    log-dbg
    log-inf
    log-err
    write-log)


(require
    racket/format
    racket/match
    racket/date
    gregor
    "../freer-monad.rkt")


(struct log-effect (level message) #:transparent)

;; Type: (-> Symbol String Any ... Free)
(define (log level message . args)
    (define formatted-message
        (if (null? args)
            message
            (apply format message args)))
    (perform (log-effect level formatted-message)))


;; Type: (-> String Any ... Free)
(define (log-dbg message . args)
    (apply log 'DEBUG message args))


;; Type: (-> String Any ... Free)
(define (log-inf message . args)
    (apply log 'INFO message args))


;; Type: (-> String Any ... Free)
(define (log-err message . args)
    (apply log 'ERROR message args))


;; Type: (-> Log-effect [(-> Log-effect Void)] Void)
(define (write-log eff [display-proc default-log-display])
    (with-handlers ([exn:fail? (lambda (exn) (error (format "error handling log effect: ~s" (exn-message exn))))])
        (display-proc eff)))

;; Type: (-> Log-effect Void)
(define (default-log-display eff)
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

(module+ test
  (require
    rackunit
    "../freer-monad.rkt")

  (test-case "log-inf: should perform an INFO log-effect with the message formatted"
    (check-match (log-inf "x ~a" 1) (impure (log-effect 'INFO "x 1") _)))

  (test-case "log-dbg: should perform a DEBUG log-effect"
    (check-match (log-dbg "d") (impure (log-effect 'DEBUG "d") _)))

  (test-case "log-err: should perform an ERROR log-effect"
    (check-match (log-err "e") (impure (log-effect 'ERROR "e") _)))

  (test-case "log-inf: should keep the message unchanged when no arguments are given"
    (check-match (log-inf "100% ~ done") (impure (log-effect 'INFO "100% ~ done") _)))

  (test-case "write-log: should raise an error that names the failure when the display procedure fails"
    (check-exn #rx"error handling log effect"
               (lambda ()
                 (write-log (log-effect 'INFO "m") (lambda (eff) (error "boom"))))))

  (test-case "default-log-display: should write INFO messages to the output port"
    ;; Given
    (define out (open-output-string))

    ;; When
    (parameterize ([current-output-port out])
      (write-log (log-effect 'INFO "hello")))

    ;; Then
    (check-regexp-match #rx"INFO :: hello" (get-output-string out)))

  (test-case "default-log-display: should write ERROR messages to the error port"
    ;; Given
    (define err (open-output-string))
    (define out (open-output-string))

    ;; When
    (parameterize ([current-error-port err]
                   [current-output-port out])
      (write-log (log-effect 'ERROR "bad")))

    ;; Then
    (check-regexp-match #rx"ERROR :: bad" (get-output-string err))
    (check-equal? (get-output-string out) "")))
