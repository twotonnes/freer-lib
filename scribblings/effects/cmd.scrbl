#lang scribble/manual

@(require
  scribble/eval
  (for-label (rename-in racket [do r:do])
             freer-lib))

@(define cmd-eval (make-base-eval))
@interaction-eval[#:eval cmd-eval (require freer-lib freer-lib/effects/cmd-effect racket/match)]

@title{System Commands}

@defmodule[freer-lib/effects/cmd-effect]

This module provides effects for executing shell commands and capturing their output.

@defstruct*[cmd-effect ([value any/c]) #:transparent]{
  An effect descriptor for running a system command. @racket[value] is the command to run; the default handler @racket[execute-command] requires it to be a string.
}

@defstruct*[cmd-result ([out string?]
                        [err string?]
                        [exit-code byte?]) #:transparent]{
  The structure returned by @racket[execute-command] after a command completes.
  @itemlist[
    @item{@racket[out]: Standard output captured as a string.}
    @item{@racket[err]: Standard error captured as a string.}
    @item{@racket[exit-code]: The exit code of the process.}
  ]
}

@defproc[(cmd [value any/c]) free?]{
  Creates an effect that requests the execution of the command @racket[value].

  @examples[#:eval cmd-eval
    (define (check-status)
      (do-m [res <- (cmd "git status")]
            (if (zero? (cmd-result-exit-code res))
                (return (cmd-result-out res))
                (return "Git check failed"))))
  ]
}

@defproc[(execute-command [value string?]) cmd-result?]{
  The default handler for @racket[cmd-effect]. It runs @racket[value] with PowerShell, by invoking @exec{powershell.exe -Command @racket[value]}, waits for the process to finish and returns a @racket[cmd-result] containing the output, error output, and exit code. A non-zero exit code is @emph{not} treated as an error.

  @exec{powershell.exe} must be available in the @envvar{PATH}. If it cannot be found, or if anything else goes wrong while running the process, an exception is raised whose message includes the command.

  A handler that uses @racket[execute-command] looks like this:

  @racketblock[
    (run (check-status)
         (lambda (eff k)
           (match eff
             [(cmd-effect c) (k (execute-command c))])))
  ]

  For testing, @racket[execute-command] can be replaced by a mock:

  @examples[#:eval cmd-eval
    (run (check-status)
         (lambda (eff k)
           (match eff
             [(cmd-effect c) (k (cmd-result "nothing to commit\n" "" 0))])))
  ]
}
