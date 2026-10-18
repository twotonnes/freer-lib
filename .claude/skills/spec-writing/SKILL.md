---
name: spec-writing
description: Use when writing functional feature specs or ADRs in design/. Follow the template, keep it lean, keep code constructs out, and make requirements testable.
---

# Spec Writing

Use this skill when writing or reviewing specs: feature specs in `design/features/` or ADRs in `design/decisions/`. Do not use it for code. How a feature is built (modules, procedures, signatures, effects, handlers) goes in `detailed-design/`; use the `detailed-design-writing` skill for that.

`design/` is for architects, who check the functional specs against the architecture. It describes behaviour as seen from outside the code. **Do not name modules, procedures, structs, contracts, or signatures.** Technology a decision chose (e.g. the Freer monad) may be named.

## When to write a spec

- **Required**: Any feature, bug fix, or refactor that changes specified behaviour.
- **Not required**: Pure refactors that don't change behaviour, or trivial fixes (e.g. typo, formatting).

## Template and location

- Start from `design/templates/feature.org` (features) or `design/templates/decision.org` (ADRs).
- Save in `design/features/<short-title>.org` or `design/decisions/NNNN-short-title.org`.
- Use Org mode: checkboxes (`- [ ]`), links (`[[file:../architecture.org][architecture]]`), and property drawers.

## Structure (skip sections that don't apply)

| Section | Purpose | Key guidance |
|---------|---------|--------------|
| **Properties** | Workflow tracking | `STATUS: draft` initially; only the user sets `accepted`; set `implemented` only when told the feature is built and tests pass. Always set `DATE`. |
| **Summary** | Orientation | One or two sentences: what and why. |
| **Scope** | Boundaries | **In scope** and **Out of scope** must both be explicit. |
| **Requirements** | What must hold | Numbered, testable statements. Each must be verifiable by a test or inspection. |
| **Architecture fit** | Check against the architecture | Which components are involved, which decisions apply, what is pure and what touches the outside world. No code constructs. Link to `architecture.org` and the detailed design. |
| **Acceptance criteria** | Done definition | Org checkboxes. Every requirement must map to at least one criterion. These form the basis of the test plan. |
| **Open questions** | Blockers | List anything unresolved. Spec cannot be accepted until these are answered. |
| **Related** | Context | Link to decisions/features this depends on or affects, and to the detailed design. |

## Small example

```org
:PROPERTIES:
:STATUS: draft
:DATE: 2026-10-09
:END:
#+TITLE: Faster generation

* Summary
Reduce program generation time by caching type generators.

* Scope
** In scope
- Cache random value generators per type used during program generation.

** Out of scope
- Caching in program evaluation or mutation.
- Changing the generation algorithm.

* Requirements
1. Generating a program of depth 4 takes <10ms on average.
2. Cache hits do not change the distribution of generated programs.

* Acceptance criteria
- [ ] Average generation time for depth-4 programs is <10ms over 1000 samples.
- [ ] Existing tests pass.
```

## Validation checklist (before submitting for acceptance)

- [ ] STATUS is `draft`.
- [ ] DATE is set.
- [ ] Summary is 1-2 sentences.
- [ ] **Out of scope** is filled in (prevents scope creep).
- [ ] Every requirement is numbered and testable.
- [ ] Every requirement maps to at least one acceptance criterion.
- [ ] Acceptance criteria use Org checkboxes.
- [ ] Open questions are listed or there are none.
- [ ] Related links to any affected decisions/features, and to the detailed design.
- [ ] No module, procedure, struct, contract, or signature names appear (check; they belong in `detailed-design/`).

## Common pitfalls

- ❌ Implementation details or code constructs in spec → Specs describe *what* and *why*, not *how*. Move *how* to `detailed-design/`.
- ❌ Vague requirements → "The system should be fast" → "Generation must complete in <X>ms".
- ❌ Missing acceptance criteria → Without checkboxes, there's no done definition.
- ❌ No out-of-scope → Leads to scope creep during implementation.

## Reference example
[[examples/state-effect-spec.org]] (copy of `design/features/state-effect.org`) is the reference for style, detail, and compactness: short sentences, behaviour only with no code constructs, one numbered requirement per behaviour, explicit out of scope, and every requirement covered by an acceptance criterion.
