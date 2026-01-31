#lang scribble/manual

@(require
    scribble/eval
    (for-label
        effect-lib))

@(define effect-lib-eval (make-base-eval))
@interaction-eval[#:eval effect-lib-eval
                  (require typed/racket effect-lib)]

@title{Command Effect}

The command effect allows you to execute system commands and capture their output in a purely functional way. This effect is platform-aware and uses the appropriate shell for your operating system.

@section{Purpose}

The command effect is designed for:
@itemlist[
  @item{Executing shell commands from Racket code}
  @item{Capturing standard output, standard error, and exit codes}
  @item{Separating command intent from execution}
  @item{Testing code that runs commands without actually executing them}
]

@section{API}

@defproc[(cmd [value String]) (Eff Any)]{
  Creates a command effect that describes running the given shell command. The command string is passed to the system shell.
  
  Returns an @racket[Eff] that, when handled, produces a @racket[cmd-result].
}

@defstruct*[(cmd-result) ([out String]
                          [err String]
                          [exit-code Byte])]{
  Contains the result of executing a command:
  @itemlist[
    @item{@racket[out]: The standard output of the command}
    @item{@racket[err]: The standard error of the command}
    @item{@racket[exit-code]: The exit code (0 for success)}
  ]
}

@defproc[(execute-command [value String]) (Eff Any)]{
  A built-in handler that executes the command immediately and returns a @racket[cmd-result]. This is the standard way to run commands with their effects.
}

@section{Example}

@codeblock{
  (with-effect-handlers ([(cmd-effect command) (execute-command command)])
    (do [result <- (cmd "echo Hello")]
        (printf "Got output: ~a~n" (cmd-result-out result))
        (return result)))
}

@section{Mock Testing}

You can test code that uses commands without actually executing them:

@codeblock{
  ;; Mock handler for testing
  (: mock-cmd-handler (-> String cmd-result))
  (define (mock-cmd-handler command)
    (cond
      [(string=? command "echo test")
       (cmd-result "test\n" "" 0)]
      [(string=? command "false")
       (cmd-result "" "" 1)]
      [else
       (cmd-result "Unknown command" "" 127)]))
  
  (with-effect-handlers ([(cmd-effect command) (return (mock-cmd-handler command))])
    (do [result <- (cmd "echo test")]
        (return (cmd-result-out result))))
}

@section{Handling Errors}

Commands can fail. Check the exit code to detect errors:

@codeblock{
  (do [result <- (cmd "some-command")]
      (if (= (cmd-result-exit-code result) 0)
          (return (cmd-result-out result))
          (error (format "Command failed: ~a" (cmd-result-err result)))))
}

@section{Multiple Commands}

You can chain multiple commands together:

@codeblock{
  (do [result1 <- (cmd "dir")]
      [result2 <- (cmd "echo Done")]
      (return (string-append (cmd-result-out result1)
                             (cmd-result-out result2))))
}

@section{Platform Notes}

- On Windows: Commands are executed via PowerShell
- On macOS/Linux: Commands are executed via the system shell

The same code works on all platforms when using platform-independent shell commands.
