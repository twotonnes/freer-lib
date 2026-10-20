---
name: review
description: Checklist and scripts for the spec review.
---

# Review

## Principles
- Judge against the stated criteria, not preference.
- Cite `file:line` for every finding, with a fix hint.
- Review only the stated criteria; do not fix.

## Spec checklist
- Each acceptance criterion is delivered.
- Nothing out of scope was changed.
- Test plan cases are covered, when a plan exists.

## Scripts
- `.claude/skills/review/scripts/changed-files.sh <allowed-path>...`: lists changed files; those outside the allowed paths, passed as arguments, are marked `OUT:`. Exit 0: no file is OUT; 1: some file is OUT; 2: usage (no path arguments).
- `.claude/skills/review/scripts/check-forbidden.sh <file>...`: lists forbidden contract forms in `.rkt` files. Exit 0: clean; 1: violations, listed in its output; 2: usage or a named `.rkt` file that does not exist.
  Non-`.rkt` arguments are skipped.
