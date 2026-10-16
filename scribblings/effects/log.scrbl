#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define log-eval (make-base-eval))
@interaction-eval[#:eval log-eval (require freer-lib freer-lib/effects/log-effect racket/match)]

@title{Logging}

@defmodule[freer-lib/effects/log-effect]

This module provides effects for logging messages at different severity levels.

@defstruct*[log-effect ([level symbol?]
                       [message string?]) #:transparent]{
  An effect descriptor for logging a message at a specified level.
  @itemlist[
    @item{@racket[level]: A symbol indicating the log level. The constructors in this module produce @racket['DEBUG], @racket['INFO] and @racket['ERROR].}
    @item{@racket[message]: The log message, already formatted.}
  ]
}

@defproc[(log-dbg [message string?] [args any/c] ...) free?]{
  Creates a logging effect that logs a message at the @racket['DEBUG] level. When @racket[args] are given, the message is produced by @racket[(apply format message args)]; otherwise @racket[message] is used as is.

  @examples[#:eval log-eval
    (define (process-data)
      (do-m [_ <- (log-dbg "Starting data processing")]
          [result <- (return 42)]
          [_ <- (log-dbg "Processing complete with result: ~a" result)]
          (return result)))
  ]
}

@defproc[(log-inf [message string?] [args any/c] ...) free?]{
  Creates a logging effect that logs a message at the @racket['INFO] level. When @racket[args] are given, the message is produced by @racket[(apply format message args)]; otherwise @racket[message] is used as is.

  @examples[#:eval log-eval
    (define (startup)
      (do-m [_ <- (log-inf "Application started")]
          (return (void))))
  ]
}

@defproc[(log-err [message string?] [args any/c] ...) free?]{
  Creates a logging effect that logs a message at the @racket['ERROR] level. When @racket[args] are given, the message is produced by @racket[(apply format message args)]; otherwise @racket[message] is used as is.

  @examples[#:eval log-eval
    (define (handle-failure)
      (do-m [_ <- (log-err "Critical failure occurred")]
          (return (void))))
  ]
}

@defproc[(write-log [eff log-effect?] [display-proc (-> log-effect? void?) default-log-display]) void?]{
  The default handler for @racket[log-effect]. Writes the log message in @racket[eff] by calling @racket[display-proc] on it. If @racket[display-proc] raises an exception, it is re-raised as an error whose message describes the failure.

  @itemlist[
    @item{@racket[eff]: The log effect to write.}
    @item{@racket[display-proc]: A procedure that displays the log message. The default (which is not exported) prints a line of the form @tt{[@italic{timestamp}] @italic{level} :: @italic{message}}, where @italic{timestamp} is the current UTC time in ISO 8601 format. @racket['ERROR] messages are written to @racket[(current-error-port)], all other levels to @racket[(current-output-port)], and the port is flushed afterwards.}
  ]

  @examples[#:eval log-eval
    (define (custom-display eff)
      (displayln (format "[~a] ~a" (log-effect-level eff) (log-effect-message eff))))
    
    (run (log-inf "Custom logging example")
         (lambda (eff k)
           (match eff
             [(log-effect level msg)
              (write-log eff custom-display)
              (k (void))])))
  ]
}

The log effect is typically used for observability and diagnostics. When logging is not wanted (e.g., in a testing environment), you can write a handler that ignores log messages or collects them for inspection.

@examples[#:eval log-eval
  (code:comment "A handler that collects log messages instead of printing them")
  (define (run-collecting-logs computation)
    (define logs '())
    (define result
      (run computation
           (lambda (eff k)
             (match eff
               [(log-effect level msg)
                (set! logs (cons (list level msg) logs))
                (k (void))]))))
    (values result (reverse logs)))

  (run-collecting-logs (process-data))
]
