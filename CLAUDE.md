# Project conventions

## Commands
- Build: `make build`
- Test: `make test`

## Stack
- Racket

## Rules
- Features are designed first in `design/` (functional specs and architecture, no code constructs; Org mode, see `design/index.org`) and are only built once their spec is accepted, within the spec's scope
- How a feature is built is designed in `detailed-design/` (modules, procedures, effects; see `detailed-design/index.org`); its detailed design is accepted before the code is written, and describes the code as it is once the feature is implemented
- When the user explicitly asks to research or investigate something, write the outcome as an Org document in `research/` (see `research/index.org`): findings with evidence, scenarios to choose from, and a recommendation. It informs specs; don't change the code as part of research
- Tests live inside source files next to the procedure that's being tested using rackunit's (module+ test)
- Pure code returns values or monads that describe effects, and never performs them; effect handlers are the only code that performs effects (see `design/decisions/0003-pure-and-effectful-code.org`). Failures (failure effect or value) mean incorrect program state; exceptions mean misuse of the API or incorrect syntax

## Guidelines
- **Think before editing**: state assumptions and plan before changing files; ask when an ambiguity changes the outcome.
- **Keep it simple**: write the least that meets the request; no speculative features or abstractions.
- **Make surgical changes**: touch only what the request needs; match existing style; no unrelated cleanup.
- **Stay focused on the goal**: verify against the acceptance criteria, stop when they are met, and report out-of-scope findings instead of acting on them.
