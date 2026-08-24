# Phase 5a: git transport error diagnostics

#flow/redgreen #model/default

## Scope

Improves user-facing diagnostics for three edge cases identified in [git-transport-review](../reviews/git-transport-review.gen.md) (observations 3, 4, 5) where raw git errors are exposed to the user instead of talkbox-formatted messages. No behaviour change to the merge/sync logic itself — only error reporting.

### Implemented from SPEC.md

No new spec aspects. Refines the user-facing diagnostics for existing spec behaviour:

- `custom_merge()` DESCENDANT_CHECK and other-branch path (observation 5).
- `merge` / `sync` default branch resolution (observation 4).
- `merge` / `sync` precondition checks (observation 3).

### Deferred

- Observation 1 (Case 1 untracked files) and observation 2 (merge/sync failure asymmetry) are handled in [Phase 5b](phase-5b-behavioural-alignment.gen.md).

## External-facing functionality

No change to command interfaces. The user sees `talkbox:`-prefixed messages instead of raw git errors in three scenarios:

- **Detached HEAD** (observation 4): `onbox merge` / `onbox sync` (and netbox/offbox analogues) with no `<branchname>` specified produce a talkbox-formatted error explaining that the current branch cannot be determined because HEAD is detached.
- **Non-existent remote ref with absent local branch** (observation 5): `onbox merge <branchname>` (and analogues) where `<branchname>` exists neither as a local branch nor as a remote-tracking branch produces a talkbox-formatted warning instead of a raw `fatal: Not a valid object name` error.
- **Uninitialised gitdir volume** (observation 3): `onbox merge` / `onbox sync` (and analogues) invoked when the gitdir volume exists but contains no initialised git repository produce a talkbox-formatted error instead of a raw git error from the sync script's `git fetch host`.

## Design

Three independent diagnostic improvements, each localised to the function where the raw error originates:

- **Observation 4** — `current_branch()` in `lib/git.sh` runs `git symbolic-ref --short HEAD`, which fails on a detached HEAD. Under `set -euo pipefail`, this causes an abrupt shell exit with git's raw `fatal: ref HEAD is not a symbolic ref` message. The fix catches the failure and produces a talkbox-formatted error (via `die`) before git's raw message reaches the user.

- **Observation 5** — `custom_merge()` in `lib/merge.sh` reaches `git branch -f "$branchname" "refs/remotes/$remote/$branchname"` in the other-branch path when the local branch is absent. If the remote-tracking ref is also absent, `git branch -f` fails with a raw `fatal: Not a valid object name` error. The fix adds a remote-ref existence check before the `git branch -f` call, producing a talkbox-formatted warning. This check is placed in `custom_merge()` (not in `descendant_check()`) to preserve the spec's DESCENDANT_CHECK semantics ("passes when `refs/heads/<branchname>` does not exist, regardless of whether `refs/remotes/<remote>/<branchname>` exists").

- **Observation 3** — `require_git_history()` in `lib/git.sh` checks `podman volume exists` but does not verify that a git repository has been initialised inside the volume. The fix adds a repository-initialisation check (e.g. verifying the presence of a `HEAD` file in the volume's mountpoint, or running a lightweight git command against the volume) and produces a talkbox-formatted error if the volume is present but uninitialised.

## Files to create / modify

- Modify `lib/git.sh` — update `current_branch()` to handle detached HEAD with a talkbox-formatted error; update `require_git_history()` to verify the gitdir volume contains an initialised repository.
- Modify `lib/merge.sh` — update `custom_merge()` to check remote-ref existence before the `git branch -f` call in the other-branch path, producing a talkbox-formatted warning when the remote ref is absent.

## Files to read during implementation

- [SPEC.md](../../SPEC.md) §"`custom_merge()`" (DESCENDANT_CHECK semantics).
- [lib/merge.sh](../../lib/merge.sh) — `custom_merge()`, `descendant_check()`, `ref_exists()`, `warn()`.
- [lib/git.sh](../../lib/git.sh) — `current_branch()`, `resolve_branches()`, `require_git_history()`.
- [lib/common.sh](../../lib/common.sh) — `die()`.
- [git-transport-review](../reviews/git-transport-review.gen.md) — observations 3, 4, 5.

## Key internal interfaces

- `lib/git.sh`:
  - `current_branch()` — now catches `git symbolic-ref` failure and calls `die` with a talkbox-formatted message instead of allowing the raw git error to propagate under `set -e`.
  - `require_git_history()` — now performs a second check after the `podman volume exists` check to verify the volume contains an initialised git repository, calling `die` with a talkbox-formatted message if not.
- `lib/merge.sh`:
  - `custom_merge()` — in the other-branch path (after DESCENDANT_CHECK passes and the branch is not the current branch), checks `ref_exists "refs/remotes/$remote/$branchname"` before calling `git branch -f`, calling `warn` and returning 1 if the remote ref is absent. This uses the existing `ref_exists()` helper.

## Tests

- **Unit tests** (`test/unit/merge.bats`):
  - `custom_merge` with a non-existent branch name (neither local nor remote-tracking ref exists) produces a `talkbox:`-prefixed warning and returns non-zero, with no `git branch -f` attempt.
- **Unit tests** (`test/unit/git.bats` or a new `test/unit/branch-resolution.bats`):
  - `current_branch()` on a detached HEAD produces a `talkbox:`-prefixed error and returns non-zero.
- **End-to-end tests** (`test/e2e/merge-sync.bats`):
  - `onbox merge <nonexistent-branch>` produces a `talkbox:`-prefixed warning and non-zero exit.
  - Detached HEAD on the host followed by `onbox merge` (no branch specified) produces a `talkbox:`-prefixed error and non-zero exit.
  - The uninitialised-gitdir-volume scenario (observation 3) is theoretical in normal usage; if a practical e2e setup is feasible (e.g. creating the volume manually without starting the container), add a test asserting the talkbox-formatted error. Otherwise, the unit-level check is sufficient.
