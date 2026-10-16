---
name: test-writing
description: Use this skill whenever writing tests for this code project.
---

# Test writing conventions
- Write tests per procedure. Cover the happy path, each failure path, and each edge case.
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
