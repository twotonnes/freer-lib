#lang scribble/manual

@(require
  (for-label (rename-in racket [do r:do])
             freer-lib))

@title{Performance}

This chapter gives guidance on writing performant code with the library, and lists pitfalls. It rests on one benchmark study, kept in the repository under @tt{research/performance-benchmark/}, with the measured tables in @tt{research/data/performance-benchmark/summary.org}. Case names such as U4 or W1 refer to that study.

@section{What was measured}

The study ran once, on one machine (Intel i7-8565U), with Racket v9.3 CS, a single run of the whole study, and the @tt{powersave} frequency governor; the machine was not idle. Read the numbers as follows.

@itemlist[
  @item{Ratios (library time over plain Racket time) and the differences between code shapes are relative. Absolute timings will vary by machine, and byte counts were not reliable in absolute terms, so none are given here.}
  @item{The cases are synthetic micro-benchmarks and workloads, up to n = 131072. A difference between two shapes is measured in a micro-benchmark, not in a real program.}
  @item{Numbers below are per operation at n = 131072, unless stated. They show what was measured on that machine, not a promise.}
]

In the workloads, a monadic step cost roughly 2 to 9 microseconds, 2.7 to 20.5 times the plain Racket version (cases W1 to W5). A bind of a finished value cost about 8 ns and one effect through the handler about 44 ns (U1, U3). Time per operation was about constant in n for most cases. Three shapes grew with n: left-nested binds, @racket[sequence], and non-tail recursion.

@section{Guidelines}

Each guideline names the case it rests on.

@itemlist[
  @item{@bold{Nest binds to the right.} A right-nested chain of binds cost 44 ns per bind at every n; a left-nested chain cost 182 ns at n = 131072 and rose with n (case U4). A sequence of @racket[do-m] steps is right-nested.}
  @item{@bold{Prefer @racket[map-m] to @racket[sequence] over long lists.} 99 ns against 273 ns per element, and @racket[sequence] grew with n while @racket[map-m] stayed flat in the upper half of the size series (case U6). The two procedures are different operations in the benchmark, equal in intent.}
  @item{@bold{Prefer tail-recursive effectful loops when the depth is large.} 45 ns against 194 ns per step, and the non-tail version grew with n (case U5).}
  @item{@bold{Do not avoid the failure effect for speed.} @racket[try] and @racket[catch] were not slower than @tt{with-handlers} and @racket[raise] in any variant: ratios 0.84 (no failure), 0.37 (failure at depth 1) and 0.72 (failure at depth 8) (case U8).}
  @item{@bold{Do not expect handler stacking to cost much.} From 1 to 8 nested handlers the time rose by 12 ns, from 46 to 58 ns, and the plain version with wrapper procedures rose by the same 12 ns (case U7). Stacking cost is not particular to the library (an inference from that equality).}
  @item{@bold{Expect an effect to cost more than a bind.} One effect through @racket[run] cost 44 ns, a bind of a finished value 8 ns (cases U3, U1). Moving work that needs no effect into pure code, or into one handler, is the shape that benefits (an inference from these two numbers, not tested).}
]

These gains are differences between shapes at sizes up to 131072. They were not measured on a real program.

@section{Pitfalls}

@itemlist[
  @item{@bold{Deeply left-nested binds.} Left nesting, for example a bind whose first argument is itself a long chain of binds, grew from 71 ns per bind at n = 64 to 182 ns at n = 131072 (case U4). It is not quadratic, but it is the one bind shape that still grows.}
  @item{@bold{@racket[sequence] on long lists.} 107 ns per element at n = 64 and 273 ns at n = 131072 (case U6).}
  @item{@bold{Deep non-tail recursion in monadic code.} 106 ns per step at n = 64 and 194 ns at n = 131072 (case U5). The study did not separate GC from other causes of the growth. For the tree traversal workload, depth did not matter (case W4, complete and degenerate trees cost the same), so the pitfall applies to the recursion measured in U5.}
  @item{@bold{Reading a ratio as a bound on real code.} Ratios are large where the plain step is only 2 to 10 ns (cases U1 to U6, W2, W5). They show the distance to a bare loop, not to a realistic handler.}
  @item{@bold{Resuming one computation many times.} Repeated resumption cost 6.28 microseconds per resume at one fixed depth and did not grow with n (case U9). The library's design treats it as out of scope, and the study did not reproduce the larger costs recorded in the design for deep computations. Treat it as unmeasured at depth.}
  @item{@bold{Assuming the study covers your program.} No real application was measured, and a repeat run with the performance governor on an idle machine was not made.}
]

@section{Measuring your own code}

Measure your own program before you change its shape. Compile it with @tt{raco make} and run it from compiled code, not under errortrace. Warm it up, collect garbage before each timed run, repeat the run and take the median, and compare against a plain Racket version that does the same work. Vary the size n over powers of two and fit time per operation against n: a constant time per operation means the shape scales.

The repository has a @tt{make benchmark} target that follows this method. It is an example of the method only. The harness is not part of the public library, is not exported by @racketmodname[freer-lib], and its interface is not documented or stable.
