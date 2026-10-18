---
name: test-writing
description: Use this skill whenever writing tests for this code project.
---

# Test plan
Steps, in order:
1. Plan mode: return the full plan in the reply. Write no file. Base the cases on the spec's requirements and acceptance criteria and the detailed design.
2. The user approves the plan.
3. Write the approved plan to `test-plan/features/<feature>.org` (same name as the spec), starting from `test-plan/templates/feature.org`. Read `test-plan/index.org` first.
   - Set the `SPEC` and `DETAILED_DESIGN` properties, and link both in Related.
   - Add a link to the plan in the Related section of the spec and of the detailed design.
   - Fill the Coverage table so every requirement and acceptance criterion maps to cases.
4. Implementation mode: write the tests to implement the plan's cases (conventions below).

## Reference example
[[examples/state-effect-test-plan.org]] (copy of `test-plan/features/state-effect.org`) is the reference for style, detail, and compactness: cases grouped by procedure, each named and stated as Given, When, Then in one line, and a coverage table back to the spec.

# Test writing conventions
- Write tests per procedure. Cover the happy path, each failure path, and each edge case.
- The project uses no runtime contracts, so tests are the only check on types. For each procedure:
  - Pass arguments of every type its type comment allows, including the edge cases of each type.
  - Check that the result has the type in the comment.
  - Cover every branch of the procedure.
- Put each test in a `(module+ test ...)` block in the same source file as the procedure it tests.
- Use `rackunit` for every test.
- Name each test `"<procedure>: should <expected> when <condition>"`, for example `"my-procedure: should return 1 when applied"`.
- Mark the Given, When, and Then sections with comments. Skip the markers in tests under 5 lines.
- When the tested code logs, wrap the call in `(parameterize ([current-output-port (open-output-nowhere)]) ...)`.
- Run file-system tests inside `(make-temporary-directory)`, and delete the directory afterwards.

# Test example
Follow this pattern. The test sits next to the procedure it tests.

```racket
(define (add1-positive v)
    (if (positive? v)
        (add1 v)
        v))
(module+ test
    (test-case "add1-positive: should return v when v is negative"
        ;; Given
        (define v -1)

        ;; When
        (define result (add1-positive v))

        ;; Then
        (check-equal? result v)))
```
