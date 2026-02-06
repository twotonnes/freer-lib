#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do] [log-info r:log-info] [log-debug r:log-debug] [log-error r:log-error])
             freer-lib))

@(define cmd-eval (make-base-eval))
@interaction-eval[#:eval cmd-eval (require freer-lib freer-lib/effects/cmd-effect racket/match)]

@title{System Commands}

@defmodule[freer-lib/effects/cmd-effect]

This module provides effects for executing shell commands and capturing their output.

@defstruct[cmd-effect ([command string?]) #:transparent]{
  An effect descriptor for running a system command.
}

@defstruct[cmd-result ([out string?]
                       [err string?]
                       [exit-code byte?]) #:transparent]{
  The structure returned by the handler after a command completes successfully.
  @itemlist[
    @item{@racket[out]: Standard output captured as a string.}
    @item{@racket[err]: Standard error captured as a string.}
    @item{@racket[exit-code]: The integer exit code of the process.}
  ]
}

@defproc[(cmd [command string?]) impure?]{
  Creates an effect that requests the execution of @racket[command].

  @examples[#:eval cmd-eval
    (define (check-status)
      (do [res <- (cmd "echo \"checking git status\"")]
          (if (zero? (cmd-result-exit-code res))
              (return (cmd-result-out res))
              (return "Git check failed"))))
  ]
}

@defproc[(execute-command [command string?]) cmd-result?]{
  The default implementation for executing commands. It attempts to run the @racket[command] string using the system's shell (specifically targeting PowerShell on Windows environments).
  
  @itemlist[
    @item{@emph{Success}: Returns a @racket[cmd-result] structure containing the output, error output, and exit code.}
    @item{@emph{Failure}: If an error occurs during execution (such as the shell not being found), raises an exception with the error message.}
  ]

  @examples[#:eval cmd-eval
    (run (check-status)
         (lambda (eff k)
           (match eff
             [(cmd-effect c) (k (execute-command c))])))
  ]
}
