---
name: test-writing
description: Use this skill whenever writing tests for this code project.
---

# Test writing

## Test plan
1. Plan mode: reply with the full plan, from the spec and detailed design; write no file.
2. The user approves it.
3. Write it to `test-plan/features/<feature>.org` (name of the spec) from `test-plan/templates/feature.org`; read `test-plan/index.org` first. Set `SPEC` and `DETAILED_DESIGN`, link it from both, fill the Coverage table.
4. Implementation mode: write the tests.

Reference: `.claude/skills/test-writing/examples/state-effect-test-plan.org` (cases per procedure, one-line Given/When/Then, coverage table).

## Conventions
- Per procedure, cover the happy path, failures, edge cases, every branch.
- No runtime contracts: pass every type the type comment allows; check the result type.
- Use `rackunit`, in a `(module+ test ...)` block in the source file.
- Name each test `"<procedure>: should <expected> when <condition>"`; check names in rackunit files (not test plans) with `.claude/skills/test-writing/scripts/check-case-names.sh`.
- Mark Given, When, Then, except in tests under 5 lines.
- Wrap logging calls in `(parameterize ([current-output-port (open-output-nowhere)]) ...)`.

```racket
(module+ test
    (test-case "add1-positive: should return v when v is negative"
        ;; Given
        (define v -1)
        ;; When
        (define result (add1-positive v))
        ;; Then
        (check-equal? result v)))
```
