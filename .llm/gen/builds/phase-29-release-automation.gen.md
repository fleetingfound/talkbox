# Phase 29: release automation for the main/dev branch split (`.release/release.sh`)

Status: `SUCCESS`

Implements [the plan](../plans/phase-29-release-automation.gen.md): [.release/release.sh](../../../.release/release.sh) (new) is the standalone release script, and [.coreignore](../../../.coreignore) gains the `.release/` entry so the release tooling never reaches `main`. The script cuts a release from a clean `dev` worktree: it builds the main tree as the dev commit's tree minus every `.coreignore`-matched path (git gitignore semantics, plumbing-only tree construction through a temporary index), composes the release message in the user's editor (subject `talkbox v<version>`, user notes, preserved `Commit: <dev hash>` trailer), creates the main commit with `git commit-tree` over the current `main` HEAD, advances `main` with `git update-ref`, and tags the main commit `v<version>` and the dev commit `dev/v<version>` as lightweight tags, printing a summary and leaving the push to the user. All validations run before any ref changes, and every failure exits non-zero with a `release: <message>` diagnostic.

## Key design findings

- The plan specifies `git check-ignore --exclude-from`, but no such flag exists in the installed git (2.47.3). The same semantics are achieved with `git -c core.excludesFile=<extracted .coreignore> check-ignore --stdin -z --no-index` run against a throwaway `GIT_DIR`/`GIT_WORK_TREE` (a minimal fake gitdir plus an empty worktree under the script's temp directory), which makes the extracted `.coreignore` the only pattern source: the working tree's `.gitignore`, `.git/info/exclude` and the user's global excludes are all unreachable, so the filter cannot over-remove release content.
- Gitlink (submodule) entries from `git ls-tree -r` are not directories from `check-ignore`'s point of view under `--no-index`, so a trailing-slash pattern like `.opencode/` would not match the bare path `.opencode`. The script appends `/` to gitlink paths when feeding `check-ignore` and strips it from the matches, so directory patterns match submodules exactly as git itself does (verified: the release tree excludes `.opencode`, matching the hand-made `main`).
- The dev tag is created as `dev/v<version>`, matching the existing repository tags (`dev/v0.1.0`–`dev/v0.1.2`) and the existing `Source:`→`Commit:` trailer replacement in the main commit message.

## Changes

- [.release/release.sh](../../../.release/release.sh) (new): the release script described above, structured into validation, `.coreignore` extraction and path filtering, temp-index tree construction, message editing/validation, and commit/tagging steps, with usage/`-h`/`--help` and trap-based temp cleanup.
- [.coreignore](../../../.coreignore): `.release/` added so the release tooling is excluded from `main`.
- [test/runner.mk](../../../test/runner.mk): `.release/release.sh` appended to `SHELL_SCRIPTS`. Justification: the test harness was misaligned with the plan, which requires the script to pass `make lint` and `make format` — "The script must pass `make lint` (ShellCheck) and `make format` (shfmt), which the implementer should run" — while `SHELL_SCRIPTS` previously covered only `test/` scripts, so those targets did not check the new script at all.
- [MAP.gen.md](../../../MAP.gen.md): new release-tooling entry for `.release/release.sh`.
- No tests were implemented, per the plan: "Per the request, no tests are implemented for this phase."

## Verification

- `make lint` (ShellCheck, including `.release/release.sh`) and `make format`/`shfmt -d` clean.
- Manual smoke check in a scratch clone of this repository (the plan assigns the automated-suite burden to `make lint`/`make format` and the smoke check to the user):
  - happy path: main commit carries exactly the dev tree minus the `.coreignore` matches (28 paths, `.llm/`, `test/`, `Makefile`, `MAP.gen.md`, `.release/`, `.opencode` and friends excluded, byte-identical to an independently computed expected tree modulo the gitlink fix above), parent is the previous `main`, subject/notes/`Commit: <dev hash>` message as edited, `v<version>` on the main commit and `dev/v<version>` on the dev commit as lightweight tags, and the dev worktree untouched and still on `dev`;
  - failure paths all exit non-zero with `release: <message>` and leave no partial state (main ref, dev ref and tags unchanged): pre-existing tag, wrong branch, detached HEAD, dirty or untracked-file worktree, missing `main` branch, `main` checked out in another worktree, invalid version, editor non-zero exit, unedited-without-notes message, removed `Commit:` trailer and missing version in the subject;
  - message cleanup: `#` hint lines removed, leading/trailing blank lines trimmed, consecutive blanks collapsed, and chained releases parent correctly on the previous release.

- `make test-unit`: 323/323.
- `make test-e2e`: 85/85.

## Linked documents

- Plan: [phase-29-release-automation.gen.md](../plans/phase-29-release-automation.gen.md) — marked complete in the plans index.
- Choice documents: [release-script-tag-type](../choices/release-script-tag-type.gen.md), [release-script-commit-construction](../choices/release-script-commit-construction.gen.md), [release-script-message-editing](../choices/release-script-message-editing.gen.md), [release-script-push-behaviour](../choices/release-script-push-behaviour.gen.md).
- No new issue documents (the `check-ignore` flag and gitlink findings above were identified and resolved during implementation).
