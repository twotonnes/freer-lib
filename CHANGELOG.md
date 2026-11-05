# Changelog

This file records every release of freer-lib, with the newest release first. Each release has one entry, headed by its version number and date. The version follows Major.Minor.Revision: a major release contains breaking changes to the public API, a minor release adds backward-compatible features, and a revision release fixes bugs or changes documentation or performance without changing the API.

Within an entry, changes are grouped as **Breaking**, **Added**, and **Fixed**. Groups without changes are left out. A major release has a **Migration** subsection that explains how to move code from the previous major version.

## 1.1.0 (2026-11-05)

### Added

- Task effects: `spawn`, `await` and `poll` build concurrent computations; a task's outcome is a `task-success` or `task-failure` value, and `poll` answers `task-running` for a task that has not finished.
- Fork/join operations: `map-par` and `run-par` answer the outcomes of computations run in parallel, in input order; `collect-par` answers all successful values or performs the leftmost failure in the parent.
- Handler helpers: `make-parallel-task-handler` runs each spawned task on a Racket thread, `make-sequential-task-handler` runs each task inline at its first await, and `make-locked-handler` makes a single-shot handler safe when several tasks call it at once; both task handlers accept `#:fresh` to give each task its own handler instance.
- `try-failure-effect`: the failure description performed by `try` is now exported and transparent, so a task boundary and `collect-par` can perform it.

## 1.0.0 (2026-10-17)

### Breaking

- The waiting-computation structure `impure` (exported from `freer-monad.rkt`) gains a third field, `queue`, which holds the pending continuations.

### Migration

- Patterns that match `impure` (from `freer-monad.rkt`) must have three sub-patterns, not two. Change `(impure description k)` to `(impure description k _)`. The compiler rejects the two-field form with "insufficient number of fields".
- Calls that build `impure` directly, such as `(impure description k)`, must be replaced with `(perform description)`. The three-field constructor is still exported, but supplying a queue is unsupported and nothing checks it.
- `equal?` on two `impure` values made by separate `perform` calls is now `#f`; it was `#t`. Match the `impure` pattern and compare its fields instead.

## 0.0.0 (2026-10-16, retroactive)

This entry is retroactive. It records the state of `main` at commit `e792cbe`, before the versioning strategy in `design/decisions/0002-versioning-strategy.org` was adopted. It lists no changes.
