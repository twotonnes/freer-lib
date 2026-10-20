---
name: detailed-design-writing
description: "Use when writing or reviewing detailed designs in detailed-design/. Explain how an accepted spec is built in code: modules, procedures, effects, and where requirements are verified. Keep it aligned with the code."
---

# Detailed design writing

For `detailed-design/features/*.org` and `architecture.org`; specs and ADRs use `spec-writing`. A detailed design says *how* the code does what the spec says: modules, procedures, types (as comments), data structures, effects, handlers, the pure/impure boundary.

- Start from `detailed-design/templates/feature.org`; save under the spec's name; set `SPEC` and link back from the spec.
- Check status with `.claude/skills/spec-writing/scripts/check-status.sh <feature>`.

# Sections (skip those that do not apply)
- **Properties**: `STATUS: draft`, `DATE`, `SPEC`; only the user sets `accepted`; set `implemented` only when told the feature is built and tests pass.
- **Summary**: how it is built, linking the spec.
- **Modules and procedures**: each spec requirement traced to a module and procedure.
- **Design**: data, types, effects, handlers, boundary; follow `.claude/rules/` and `design/decisions/`.
- **Implementation checks**: where each acceptance criterion of the spec is verified (which tests, which procedures), plus checks that exist only because of this design.
- **Open questions**: block acceptance until answered.
- **Related**.

# Rules
- Never contradict the spec; change the spec first.
- Changing an `accepted` design sets it to `draft`.
- For an `implemented` feature, describe the code as it is: fix the document, not the code.
- When a feature is built, update `detailed-design/architecture.org` (module table, data flow, effect-to-handler map) in the same change.
- Do not restate what the code and Scribble docs already say, such as each procedure's type. Record why the code has its shape and which requirement each part realises.

# Checklist (before submitting for acceptance)
- [ ] STATUS is `draft`, DATE and SPEC are set.
- [ ] Every requirement of the spec maps to a module and procedure.
- [ ] Every acceptance criterion of the spec maps to an implementation check.
- [ ] Effects, handlers, and the pure/impure boundary are stated.
- [ ] Nothing contradicts the spec or the decisions.
- [ ] `detailed-design/architecture.org` is updated if modules, data flow, or effects change.
- [ ] Open questions are listed or there are none.

# Reference
`.claude/skills/detailed-design-writing/examples/state-effect-detailed-design.org`.
It shows the expected style, level of detail, and compactness of a detailed design, and its traceability to the spec.
