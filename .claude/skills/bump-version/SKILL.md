---
name: bump-version
description: Use when bumping the freer-lib version for a release. Takes a level (major, minor, patch or revision), updates the version in info.rkt, adds a CHANGELOG.md entry, and runs the tests. Never commits, tags or pushes.
---

# Bump version

Apply `design/decisions/0002-versioning-strategy.org`. The level is `major` (breaking), `minor` (additions) or `patch` (fixes, docs, performance), with `revision` as an alias for `patch`; if missing or invalid, ask.

# Steps
1. **Collect the changes.** Use those the user gave; otherwise list commits since `git describe --tags --abbrev=0` (`git log --oneline <tag>..HEAD`). Sort into Breaking, Added or Fixed; ask about any unsure. Omit refactors, tests and housekeeping.
2. **Migration (major only).** The entry needs Migration steps; if the user gave none, stop and ask before editing.
3. **Write the entry** to a file (no `##` heading; the script adds `## X.Y.Z (date)`): `### Breaking`, `### Added`, `### Fixed`, `### Migration` (major); omit empty groups; one line per item.
4. **Run** `.claude/skills/bump-version/scripts/bump-version.sh <level> [entry-file]`. It reads the version, computes the next, rewrites `info.rkt`, inserts the entry, runs the tests. Exit 2 means bad usage or a missing entry file or version (nothing edited); otherwise it exits with the test result. On failure, report and leave the edits.
5. Report the new version.

# Commit and tag
Do not commit, tag or push unprompted. When the user asks for the tag, give, for the release commit on `main`:
```sh
git tag -a vX.Y.Z -m "freer-lib X.Y.Z"
```
Push only when asked.
