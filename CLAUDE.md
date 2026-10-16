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
