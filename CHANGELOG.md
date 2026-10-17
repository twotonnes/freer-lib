# Changelog

This file records every release of freer-lib, with the newest release first. Each release has one entry, headed by its version number and date. The version follows Major.Minor.Revision: a major release contains breaking changes to the public API, a minor release adds backward-compatible features, and a revision release fixes bugs or changes documentation or performance without changing the API.

Within an entry, changes are grouped as **Breaking**, **Added**, and **Fixed**. Groups without changes are left out. A major release has a **Migration** subsection that explains how to move code from the previous major version.

## 1.0.0 (2026-10-17)

### Breaking

- The waiting-computation structure `impure` (exported from `freer-monad.rkt`) gains a third field, `queue`, which holds the pending continuations.

### Migration

- Patterns that match `impure` (from `freer-monad.rkt`) must have three sub-patterns, not two. Change `(impure description k)` to `(impure description k _)`. The compiler rejects the two-field form with "insufficient number of fields".
- Calls that build `impure` directly, such as `(impure description k)`, must be replaced with `(perform description)`. The three-field constructor is still exported, but supplying a queue is unsupported and nothing checks it.
- `equal?` on two `impure` values made by separate `perform` calls is now `#f`; it was `#t`. Match the `impure` pattern and compare its fields instead.

## 0.0.0 (2026-10-16, retroactive)

This entry is retroactive. It records the state of `main` at commit `e792cbe`, before the versioning strategy in `design/decisions/0002-versioning-strategy.org` was adopted. It lists no changes.
