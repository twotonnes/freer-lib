---
name: code-writing
description: Use this skill whenever writing or changing production Racket code in this project.
---

# Code writing conventions

- Follow `.claude/rules/pure-code.md` and `.claude/rules/monadic-code.md`; do not restate them in comments or reports.
- Copy the pattern of similar project code: naming, `provide` forms, comment density.
- Style reference: `.claude/skills/code-writing/examples/state-effect.rkt.txt` (not a compiled module). Its `(module+ test ...)` block is the test-writer's; never write it.

# Layout
- `#lang racket/base`, one `provide` (one export per line), one `require` (one module per line), then effect descriptors, then procedures. Remove unused `require`s.
- Keep procedures short; logic in pure procedures, handlers small.
- Impure procedures end in `!` or name the effect. Names are lowercase, hyphenated.

# Failures
- No runtime contracts (`design/decisions/0001-no-contracts.org`).
- Model failures as values or the `failure` effect; raise only for incorrect syntax, API misuse, or outside-world errors in impure helpers (`design/decisions/0003-pure-and-effectful-code.org`).
- Wrap calls that can raise, such as `/`, in `with-handlers`.

# Type comments
Write one line above each procedure definition, and keep it in sync with the signature:
`;; Type: (-> Integer (Listof String) Free)`
- Use these names: `Integer`, `Natural`, `Real`, `String`, `Symbol`, `Boolean`, `Bytes`, `Void`, `Any`, `(Listof T)`, `(U A B)`, `HashEq`, `(Pairof A B)`, `Free` for a freer monad value, `(-> A B ... Result)` for procedures, `(->* (Required ...) (Optional ...) Result)` for optional arguments.
- For an impure procedure, add a line `;; Impure: <the effect it performs and what it raises>`.
- Check them with `.claude/skills/code-writing/scripts/check-type-comments.sh`.

# Tests
Do not write or change tests (`test-writing` skill).

# Commands
- One file: `raco make path/to/file.rkt`. Build: `make build`.
- Quiet full test run: `.claude/skills/code-writing/scripts/test.sh`.
