---
name: code-writing
description: Use this skill whenever writing or changing production Racket code in this project.
---

# Code writing conventions
- Follow `.claude/rules/pure-code.md` and `.claude/rules/monadic-code.md`. They define the pure/impure split and the monadic style; do not restate them in code comments or reports.
- Before writing, find similar code in the project and copy its pattern: naming, `provide` forms, comment density.
- Change only what the request needs. Do not refactor unrelated code.

# Reference example
`.claude/skills/code-writing/examples/state-effect.rkt.txt` (a reference copy of `effects/state-effect.rkt`, not a compiled module) is the reference for style, level of detail, and compactness. Read it before writing a new module. Its `(module+ test ...)` block shows how the test-writer's tests sit in the file; the code-writer never writes that block.

# Module layout
- Start with `#lang racket/base`.
- Then one `provide` form, one export per line. Then one `require` form, one module per line.
- Then effect descriptors (record types), then procedures. Pure and impure procedures may share a file.
- Keep each procedure short. Keep logic in pure procedures and handlers small.
- After editing, remove each `require` the file no longer uses.

# Naming
- Name each impure procedure with a `!` suffix, or with a name that states the effect.
- Use lowercase words joined by hyphens, as in the example.

# Failures and exceptions
- No runtime contracts (`define/contract`, `->`, `->i`, `provide/contract`). See `design/decisions/0001-no-contracts.org`.
- Model failures (incorrect program state, such as a missing key) as values or the `failure` effect. Raise exceptions only for incorrect syntax or API misuse, and from impure helpers for outside-world errors. See `design/decisions/0003-pure-and-effectful-code.org`.
- Wrap calls that can raise, such as `/`, in `with-handlers` and return the result as a value.

# Type comments
Write one line above each procedure definition, and keep it in sync with the signature:
`;; Type: (-> Integer (Listof String) Free)`
- Use these names: `Integer`, `Natural`, `Real`, `String`, `Symbol`, `Boolean`, `Bytes`, `Void`, `Any`, `(Listof T)`, `(U A B)`, `Free` for a freer monad value, `(-> A B ... Result)` for procedures.
- For an impure procedure, add a line `;; Impure: <the effect it performs and what it raises>`.

# Tests
- Do not write or change tests. Leave every `(module+ test ...)` block alone; the test-writer owns them (`test-writing` skill).
- Tests use `rackunit`.

# Commands
- Compile one file while iterating: `raco make path/to/file.rkt`.
- Build: `make build`. Test: `make test`.
- Redirect output to a log and read it only on failure: `make test > /tmp/freer-test.log 2>&1; echo "exit $?"`, then `grep -n -A8 -E 'error|expected|unbound|FAILURE' /tmp/freer-test.log | head -100`.
