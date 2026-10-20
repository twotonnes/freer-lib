---
name: delegation
description: How to brief an agent and what its reply must contain.
---

# Delegation

## Principles
- Agents start with no context; the brief must stand alone.
- One bounded task per agent; a fresh agent each time.
- Every brief has acceptance criteria that can be checked.

## Brief template
- **Goal**: one sentence.
- **Inputs**: paths to read.
- **Acceptance criteria**: checkable statements.
- **Constraints**: scope, allowed paths, rules.
- **Output format**: what to return, and where.
- **Verification**: scripts or commands to run before replying.

## Reply template
At most 200 words:
- **Status**: done or blocked.
- **Files**: changed paths, one line each.
- **Verification result**: commands run and outcomes.
- **Deviations or open issues**.

## Plan then implement
1. Send a plan-only brief: the implementer replies with a plan and changes no file.
2. The orchestrator checks the plan against the acceptance criteria.
3. Send a fresh implement brief that quotes the approved plan verbatim.
