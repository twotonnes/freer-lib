#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [log-info r:log-info] [log-debug r:log-debug] [log-error r:log-error])
             freer-lib))

@(define log-eval (make-base-eval))
@interaction-eval[#:eval log-eval (require freer-lib freer-lib/effects/log-effect racket/match)]

@title{Logging}

@defmodule[freer-lib/effects/log-effect]

This module provides effects for logging messages at different severity levels.

@defstruct[log-effect ([level symbol?]
                       [message string?]) #:transparent]{
  An effect descriptor for logging a message at a specified level.
  @itemlist[
    @item{@racket[level]: A symbol indicating the log level (e.g., @racket['DEBUG], @racket['INFO], @racket['ERROR]).}
    @item{@racket[message]: The log message as a string.}
  ]
}

@defproc[(log-debug [message string?] [args any/c] ...) free?]{
  Creates a logging effect that logs a @racket[message] at the DEBUG level. Supports format strings with additional arguments for formatting.

  @examples[#:eval log-eval
    (define (process-data)
      (do [_ <- (log-debug "Starting data processing")]
          [result <- (return 42)]
          [_ <- (log-debug "Processing complete with result: ~a" result)]
          (return result)))
  ]
}

@defproc[(log-info [message string?] [args any/c] ...) free?]{
  Creates a logging effect that logs a @racket[message] at the INFO level. Supports format strings with additional arguments for formatting.

  @examples[#:eval log-eval
    (define (startup)
      (do [_ <- (log-info "Application started")]
          (return (void))))
  ]
}

@defproc[(log-error [message string?] [args any/c] ...) free?]{
  Creates a logging effect that logs a @racket[message] at the ERROR level. Supports format strings with additional arguments for formatting.

  @examples[#:eval log-eval
    (define (handle-failure)
      (do [_ <- (log-error "Critical failure occurred")]
          (return (void))))
  ]
}

@defproc[(default-log-display [eff log-effect?]) void?]{
  The default handler for displaying log messages. Routes ERROR level messages to @racket[current-error-port] and other levels to @racket[current-output-port]. Automatically formats messages using @racket[default-log-format] and flushes the output.
}

@defproc[(write-log [eff log-effect?] [display-proc (-> log-effect? void?) default-log-display]) void?]{
  Writes a log message using a customizable display function.
  
  @itemlist[
    @item{@racket[eff]: The log effect to write.}
    @item{@racket[display-proc]: A function that handles displaying the log message (default: @racket[default-log-display]).}
  ]

  @examples[#:eval log-eval
    (define (custom-display eff)
      (displayln (format "[~a] ~a" (log-effect-level eff) (log-effect-message eff))))
    
    (run (log-info "Custom logging example")
         (lambda (eff k)
           (match eff
             [(log-effect level msg)
              (write-log eff custom-display)
              (k (void))])))  
  ]
}

@bold{Error Handling}: The log effect is typically used for observability and diagnostics. It does not produce errors itself, but can be combined with other effects. When logging is not available (e.g., in a testing environment), you can write a handler that ignores log messages or collects them for inspection.

@examples[#:eval log-eval
  ;; Example handler that prints logs to stdout with timestamp
  (define (run-with-logging computation)
    (run computation
         (lambda (eff k)
           (match eff
             [(log-effect level msg)
              (k (write-log eff))]))))
]
