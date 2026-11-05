#lang scribble/manual

@(require
  (for-label (rename-in racket [do r:do])
             freer-lib))

@title{Tasks}

@defmodule[freer-lib/effects/task-effect]

Tasks describe work that may run concurrently: @racket[spawn] describes starting a computation as a task, @racket[await] waits for its outcome, and @racket[poll] checks without waiting. This module ships the effect descriptions, the outcome values tasks answer, and the fork/join operations built from the task effects. It ships no handler; the @racketmodname[freer-lib/task-handlers] module ships those.

A task's outcome is either a success with the task's final value or a failure with the failure value the task's own failure catching answered. A failure inside a task stays in its outcome: it does not reach the parent's @racket[catch].

@defstruct*[spawn-effect ([computation free?])]{
  The description of the start of a task running @racket[computation]. A handler receives it and answers a task handle. Built with @racket[(spawn-effect #:computation computation)]; the field is read with @racket[spawn-effect-computation].
}

@defstruct*[await-effect ([handle any/c])]{
  The description of a wait for the task named by @racket[handle]. A handler receives it and answers the task's outcome. Built with @racket[(await-effect #:handle handle)]; the field is read with @racket[await-effect-handle].
}

@defstruct*[poll-effect ([handle any/c])]{
  The description of a check of the task named by @racket[handle]. A handler receives it and answers the task's outcome or @racket[task-running]. Built with @racket[(poll-effect #:handle handle)]; the field is read with @racket[poll-effect-handle].
}

@defstruct*[task-success ([value any/c]) #:transparent]{
  The outcome of a task that finished with @racket[value].
}

@defstruct*[task-failure ([value any/c]) #:transparent]{
  The outcome of a task whose failure catching answered the fallback value @racket[value].
}

@defstruct*[task-running () #:transparent]{
  The answer of @racket[poll] when the task has not finished. An ordinary value, not a failure: an enclosing @racket[catch] does not consume it.
}

@defproc[(spawn [computation free?]) free?]{
  Type: @racket[(-> Free Free)]. Describes @racket[spawn-effect]: starting @racket[computation] as a concurrent task. The computation's result is the task handle the handler resumes with. Nothing runs until a handler answers the description, and a finished task is never run again.
}

@defproc[(await [handle any/c]) free?]{
  Type: @racket[(-> Any Free)]. Describes @racket[await-effect]: a wait for the task named by @racket[handle] to finish. The computation's result is the task's outcome, a @racket[task-success] or @racket[task-failure]. Awaiting a finished task answers its recorded outcome without running it again.
}

@defproc[(poll [handle any/c]) free?]{
  Type: @racket[(-> Any Free)]. Describes @racket[poll-effect]: a check of the task named by @racket[handle] without waiting. The computation's result is the task's outcome when it has finished, or @racket[task-running] when it has not; in the first case the task is not run again.
}

@defproc[(map-par [f (-> any/c free?)] [xs (listof any/c)]) free?]{
  Type: @racket[(-> (-> Any Free) (Listof Any) Free)]. Spawns @racket[(f x)] for each element of @racket[xs] and awaits every task, answering the outcomes in input order. Built from @racket[spawn] and @racket[await]; it performs no effect of its own.

  Building a computation is not running it. @racket[f] is applied in the parent, but it only @emph{describes} the work: the task handler later runs the built computation on the task's own thread, and everything described between the effects runs there with it. Work eagerly wrapped in @racket[return] runs in the parent instead: @racket[(lambda (x) (return (fib x)))] computes @racket[(fib x)] while @racket[map-par] builds, before any task starts. Describe work with @racket[do-m] steps so it runs inside the task. The same holds for the computations given to @racket[run-par].
}

@defproc[(run-par [ms (listof free?)]) free?]{
  Type: @racket[(-> (Listof Free) Free)]. Spawns each computation of @racket[ms] and awaits every task, answering the outcomes in the order the computations were given. Built from @racket[spawn] and @racket[await]; it performs no effect of its own.
}

@defproc[(collect-par [outcomes (listof (or/c task-success? task-failure?))]) free?]{
  Type: @racket[(-> (Listof (U task-success task-failure)) Free)]. Given the outcomes of a parallel run, answers the list of successful values, left to right, without performing any effect. When an outcome is a @racket[task-failure], performs the parent's failure effect with the task's failure value as the fallback, so the parent's @racket[catch] answers the leftmost failing task's value. Using it is a choice: without it, the parent answers every outcome and decides itself. Raises @racket[exn:fail] when given a value that is not an outcome.
}

@section{Task Handlers}

@defmodule[freer-lib/task-handlers]

This module ships the handlers that give the task effects their meanings. The parallel handler runs each spawned task on a Racket thread; the sequential handler runs each task inline at its first await, which makes a program deterministic for tests. The same program answers the same outcomes under both, except where the program depends on real-world timing.

Both task handlers delegate every description that is not a task effect to the wrapped handler they are built from, and both re-raise a task's exception at the parent's await. The library's helpers use only what is safe under parallel threads; to make a stateful handler of your own safe when tasks share it, wrap it with @racket[make-locked-handler].

@defproc[(make-parallel-task-handler [base (-> any/c (-> any/c free?) free?)]
                                      [#:fresh fresh (-> (-> any/c (-> any/c free?) free?)) #f])
         (-> any/c (-> any/c free?) free?)]{
  Type: @racket[(-> (-> Any (-> Any Free) Free) [#:fresh (-> (-> Any (-> Any Free) Free))] (-> Any (-> Any Free) Free))]. Impure: the answered handler starts a Racket thread per spawned task, waits on that thread at each await, and checks with @racket[thread-dead?] at each poll. When @racket[fresh] is given, it is called at each spawn to build the base the new task runs its non-task effects through, so tasks share handler state only when the caller shares it.
}

@defproc[(make-sequential-task-handler [base (-> any/c (-> any/c free?) free?)]
                                        [#:fresh fresh (-> (-> any/c (-> any/c free?) free?)) #f])
         (-> any/c (-> any/c free?) free?)]{
  Type: @racket[(-> (-> Any (-> Any Free) Free) [#:fresh (-> (-> Any (-> Any Free) Free))] (-> Any (-> Any Free) Free))]. Impure: the answered handler records each spawned task and runs it inline at its first await, on the caller's thread; @racket[poll] answers @racket[task-running] for a task that has not run and the outcome once it has. Nothing runs while a task is only spawned, so each task runs at its first await, in await order. The same @racket[#:fresh] option exists as on the parallel handler.
}

@defproc[(make-locked-handler [wrapped (-> any/c (-> any/c free?) free?)])
         (-> any/c (-> any/c free?) free?)]{
  Type: @racket[(-> (-> Any (-> Any Free) Free) (-> Any (-> Any Free) Free))]. Impure: the answered handler waits on a semaphore around @racket[wrapped]'s answer and hands the lock back before it resumes the continuation, so the stateful answer is serialised while the code after the effect is not. Wrapping once and sharing the wrapper serialises every task calling it. Only defined for single-shot handlers, those answering each description by resuming their @racket[k] exactly once; it raises @racket[exn:fail] when @racket[wrapped] does not. For a handler that answers by returning a computation, or that resumes its @racket[k] more than once, give each task a fresh handler with @racket[#:fresh] instead.
}

@defproc[(task-handle? [v any/c]) boolean?]{
  Type: @racket[(-> Any Boolean)]. Recognises the handles the task handlers answer @racket[spawn] with. Handles are opaque: there is no constructor and no accessor, only this predicate.
}

Awaiting in a circle deadlocks. Awaiting or polling a handle from another run, or from another handler instance, is not checked and does nothing useful. A task that never finishes makes @racket[await] wait forever.

@bold{Example.} The same program answers the same outcomes under both handlers.

@racketblock[
(define base
  (lambda (desc k)
    (error "unexpected effect")))

(define par-h (make-parallel-task-handler base))
(define seq-h (make-sequential-task-handler base))

(run (map-par (lambda (x) (return (* x x))) '(1 2 3)) par-h)
(run (map-par (lambda (x) (return (* x x))) '(1 2 3)) seq-h)
]
