---
name: detailed-design-writing
description: Use when writing or reviewing detailed designs in detailed-design/. Explain how an accepted spec is built in code: modules, procedures, effects, and where requirements are verified. Keep it aligned with the code.
---

# Detailed Design Writing

Use this skill when writing or reviewing detailed designs in `detailed-design/` (`features/*.org` and `architecture.org`). For specs and ADRs in `design/`, use the `spec-writing` skill.

`design/` says *what* the system does and is free of code constructs. `detailed-design/` says *how* the code does it, for implementers: module and procedure names, signatures and types (as comments; no runtime contracts), data structures, effects and handlers, and the pure/impure boundary.

## Template and location
- Start from `detailed-design/templates/feature.org`.
- Save in `detailed-design/features/<short-title>.org`, with the same name as the spec in `design/features/`.
- Link the spec in the `SPEC` property, and link back from the spec to the detailed design.

## Structure (skip sections that don't apply)

| Section | Purpose | Key guidance |
|---------|---------|--------------|
| **Properties** | Workflow tracking | `STATUS: draft` initially; only the user sets `accepted`; set `implemented` only when told the feature is built and tests pass. Set `DATE` and `SPEC`. |
| **Summary** | Orientation | One or two sentences: how the feature is built, linking the spec. |
| **Modules and procedures** | Traceability | Which requirement of the spec is realised by which module and procedure. Every spec requirement appears. |
| **Design** | The shape of the code | Data structures, signatures and types, effects described and how they are handled, the pure/impure boundary. Follow `.claude/rules/` (pure code, freer-lib) and `design/decisions/`. |
| **Implementation checks** | Verification | Where each acceptance criterion of the spec is verified (which tests, which procedures), plus checks that exist only because of this design. |
| **Open questions** | Blockers | Implementation questions. The design cannot be accepted until they are answered. |
| **Related** | Context | The spec, decisions, other detailed designs this depends on or affects. |

## Rules
- A detailed design may name code constructs; it must not contradict the spec. If the design would need a different behaviour, change the spec first.
- Change an `accepted` detailed design only by setting it back to `draft`.
- For a feature that is `implemented`, the detailed design describes the code **as it is**. Read the code and fix the document, never the other way round.
- When a feature is built, update `detailed-design/architecture.org` (module table, data flow, effect-to-handler map) in the same change.
- Do not repeat what the code and the Scribble documentation already state, such as each procedure's type. Record why the code has its shape, and which requirement each part realises.

## Validation checklist (before submitting for acceptance)
- [ ] STATUS is `draft`, DATE and SPEC are set.
- [ ] Every requirement of the spec maps to a module and procedure.
- [ ] Every acceptance criterion of the spec maps to an implementation check.
- [ ] Effects, handlers, and the pure/impure boundary are stated.
- [ ] Nothing contradicts the spec or the decisions.
- [ ] `detailed-design/architecture.org` is updated if modules, data flow, or effects change.
- [ ] Open questions are listed or there are none.
