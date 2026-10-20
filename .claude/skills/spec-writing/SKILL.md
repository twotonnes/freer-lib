---
name: spec-writing
description: Use when writing functional feature specs or ADRs in design/. Follow the template, keep it lean, keep code constructs out, and make requirements testable.
---

# Spec writing

For specs in `design/features/` and ADRs in `design/decisions/`. How a feature is built goes in `detailed-design/` (`detailed-design-writing` skill). Specs are for architects: describe behaviour only; **name no modules, procedures, structs, contracts or signatures**. A decision may name its technology.

- Start from `design/templates/feature.org` or `decision.org`; save as `design/features/<short-title>.org` or `design/decisions/NNNN-short-title.org`. Use Org checkboxes, links and property drawers.
- Check a feature's status with `.claude/skills/spec-writing/scripts/check-status.sh <feature>`.

# When to write a spec
- Required: any feature, bug fix, or refactor that changes specified behaviour.
- Not required: pure refactors that keep behaviour, or trivial fixes (typo, formatting).

# Sections (skip those that do not apply)
- **Properties**: `STATUS: draft`, `DATE`; only the user sets `accepted`; set `implemented` only when told the feature is built and tests pass.
- **Summary**: one or two sentences, what and why.
- **Scope**: explicit In scope and Out of scope.
- **Requirements**: numbered, testable.
- **Architecture fit**: which components and decisions are involved, what is pure and what touches the outside world; no code constructs. Link `architecture.org` and the detailed design.
- **Acceptance criteria**: checkboxes; every requirement maps to one; they seed the test plan.
- **Open questions**: block acceptance.
- **Related**: linked decisions, features, detailed design.

# Checklist (before submitting for acceptance)
- [ ] STATUS is `draft`.
- [ ] DATE is set.
- [ ] Summary is 1-2 sentences.
- [ ] Out of scope is filled in.
- [ ] Every requirement is numbered and testable.
- [ ] Every requirement maps to at least one acceptance criterion.
- [ ] Acceptance criteria use Org checkboxes.
- [ ] Open questions are listed or there are none.
- [ ] Related links affected decisions, features, and the detailed design.
- [ ] No module, procedure, struct, contract, or signature names appear.

# Pitfalls
- Implementation details in a spec: describe what and why; move how to `detailed-design/`.
- Vague requirements: not "the system should be fast" but "generation completes in <X>ms".
- Missing acceptance criteria: without checkboxes there is no done definition.
- No out of scope: leads to scope creep.

# Reference
`.claude/skills/spec-writing/examples/state-effect-spec.org`.
It shows the expected style, level of detail, and compactness of a spec.
