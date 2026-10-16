---
name: bump-version
description: Use when bumping the freer-lib version for a release. Takes a level (major, minor or revision), updates the version in info.rkt, adds a CHANGELOG.md entry, and runs the tests. Never commits, tags or pushes.
---

# Bump version

Apply the versioning strategy in `design/decisions/0002-versioning-strategy.org`. The version is the `version` field in `info.rkt`. The changelog is `CHANGELOG.md`, which holds one entry per release, newest first.

The skill is invoked with a level: `major`, `minor` or `revision`. If the level is missing or not one of these, stop and ask.

## Levels

- **major**: any breaking change to the public API. X+1.0.0.
- **minor**: backward-compatible additions. X.Y+1.0.
- **revision**: fixes, documentation and performance changes that keep the API. X.Y.Z+1.

## Steps

1. **Read the current version.** Read the `version` field from `info.rkt`. If it is missing, stop and report that.

2. **Compute the next version** from the level. Show the old and new version.

3. **Collect the changes.**
   - If the user gave changes in the request, use them.
   - Otherwise list commits since the last release tag: `git log --oneline <latest-tag>..HEAD`, where the latest tag is `git describe --tags --abbrev=0`. Sort each change into Breaking, Added or Fixed. Ask the user about any change you cannot sort with confidence.
   - Leave out commits that are only refactors, tests or housekeeping, unless they change the public API.

4. **Check the migration notes for a major bump.** A major release needs a **Migration** subsection in its new entry, with the steps a user takes to move from the previous major version. If the user has not supplied migration steps, or they are empty, stop and ask for them. Do not edit any file until they are given.

5. **Update `info.rkt`.** Change only the `version` field to the new version.

6. **Add the CHANGELOG.md entry.**
   - Insert the new entry directly below the header, above the previous entry. Keep the header text and the older entries unchanged.
   - Heading: `## X.Y.Z (YYYY-MM-DD)`, with today's date from `date +%F`.
   - Subsections, in this order: `### Breaking`, `### Added`, `### Fixed`, then `### Migration` for a major release. Leave out empty groups. Each item is one short line.

7. **Run the tests.** Run `make test` from the repository root. If it fails, stop, report the failure, and leave the edits in place for the user to inspect. Do not try to fix the failure silently.

8. **Report.** State the new version, the files changed (`info.rkt`, `CHANGELOG.md`), and that nothing was committed, tagged or pushed.

## Commit and tag

Do not commit, create a tag or push. Once the user has committed the release and asks for the tag, give them this command, to be run on the release commit on `main`:

```sh
git tag -a vX.Y.Z -m "freer-lib X.Y.Z"
```

Replace `X.Y.Z` with the new version. The tag must be annotated (`-a`). Do not run the command without the user asking for it, and do not push the tag unless asked.

## Pitfalls

- ❌ Setting a version while work is still in progress → Set it only when the release is complete and tested.
- ❌ Writing a major entry without a Migration subsection → Stop before editing (step 4).
- ❌ Creating a lightweight tag → Always use `git tag -a`.
- ❌ Committing or pushing as part of the bump → Never do this; the user does it.
