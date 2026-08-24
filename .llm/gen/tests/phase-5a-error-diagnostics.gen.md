# Tests: Phase 5a git transport error diagnostics

Linked plan: [phase-5a-error-diagnostics.gen.md](../plans/phase-5a-error-diagnostics.gen.md)

Summary: this phase adds failing tests for the three git-transport diagnostic improvements from [git-transport-review.gen.md](../reviews/git-transport-review.gen.md) observations 3, 4 and 5 — a talkbox-formatted error for a detached HEAD during default-branch resolution, a talkbox-formatted warning for a merge of a branch that exists neither locally nor as a remote-tracking ref, and a talkbox-formatted error when the gitdir volume exists but contains no initialised git repository.

The tests pin the following interfaces, which the implementation must provide so that the tests pass once the plan is implemented:

- `lib/git.sh` `current_branch()` — on a detached HEAD the raw `git symbolic-ref --short HEAD` failure is caught and `die` is called with a `talkbox:`-prefixed message (instead of the shell aborting with git's raw `fatal: ref HEAD is not a symbolic ref` under `set -e`).
- `lib/merge.sh` `custom_merge()` — in the other-branch path (after DESCENDANT_CHECK passes and the branch is not the current branch), the remote ref `refs/remotes/<remote>/<branchname>` is checked with the existing `ref_exists()` helper before `git branch -f`, and `warn` is called with a `talkbox:`-prefixed message (instead of git's raw `fatal: not a valid object name`) when the ref is absent.
- `lib/git.sh` `require_git_history()` — after the `podman volume exists` check, the gitdir volume is verified to contain an initialised git repository, with a `talkbox:`-prefixed `die` message when the volume is present but uninitialised.

## New tests

Unit tests (`test/unit/merge.bats`, 1 test added):

- `custom_merge warns and creates nothing when neither local nor remote branch exists` - with a branch name present in neither `refs/heads/` nor `refs/remotes/<remote>/`, `custom_merge` exits non-zero, emits a `talkbox:`-prefixed warning with no raw `fatal:` output, does not create the local branch ref, and leaves the current checkout unchanged.

This pins the plan's "`custom_merge` with a non-existent branch name (neither local nor remote-tracking ref exists) produces a `talkbox:`-prefixed warning and returns non-zero, with no `git branch -f` attempt", together with [SPEC.md §`custom_merge()`](../../../SPEC.md) (DESCENDANT_CHECK "passes when `refs/heads/<branchname>` does not exist, regardless of whether `refs/remotes/<remote>/<branchname>` exists" — which is what lets control reach the other-branch path here).

Unit tests (`test/unit/git.bats`, 1 test added):

- `current_branch on a detached HEAD produces a talkbox error` - with the fixture repository on a detached HEAD, `current_branch` exits non-zero and emits a `talkbox:`-prefixed error with no raw `fatal:` output.

This pins the plan's "`current_branch()` on a detached HEAD produces a `talkbox:`-prefixed error and returns non-zero".

End-to-end tests (`test/e2e/merge-sync.bats`, 3 tests added), run under the existing `systemd-run`-wrapped runner on a temporary git project with a tracked file:

- `onbox merge <nonexistent-branch> warns with a talkbox message and exits non-zero` - after the onbox container and gitdir volume are initialised, `onbox merge nosuchbranch` exits non-zero and emits a `talkbox:`-prefixed warning with no raw `fatal:` output.
- `onbox merge with a detached host HEAD errors with a talkbox message and exits non-zero` - after the onbox container and gitdir volume are initialised and the host HEAD is detached, `onbox merge` with no branch exits non-zero and emits a `talkbox:`-prefixed error with no raw `fatal:` output.
- `onbox merge on an uninitialised gitdir volume errors with a talkbox message` - with only a bare gitdir volume created (the container never started, so no repository initialised inside it), `onbox merge` exits non-zero and emits a `talkbox:`-prefixed error with no raw `fatal:` output.

These pin the plan's "`onbox merge <nonexistent-branch>` produces a `talkbox:`-prefixed warning and non-zero exit", "Detached HEAD on the host followed by `onbox merge` (no branch specified) produces a `talkbox:`-prefixed error and non-zero exit", and the uninitialised-gitdir-volume scenario ("if a practical e2e setup is feasible (e.g. creating the volume manually without starting the container), add a test asserting the talkbox-formatted error").

## Tests edited

None. The three new unit tests and three new end-to-end tests are additions to existing files (`test/unit/merge.bats`, `test/unit/git.bats`, `test/e2e/merge-sync.bats`); no pre-existing test assertion was changed.

## Tests removed

None. No pre-existing test is inconsistent with the plan:

- No existing test invokes `current_branch()` on a detached HEAD or asserts the raw `fatal: ref HEAD is not a symbolic ref` message; the plan's `current_branch()` change is therefore unopposed.
- The existing `custom_merge` tests that exercise the other-branch path (`custom_merge creates a new branch without switching when the branch does not exist`, `custom_merge advances an existing non-current branch without switching`) all have `refs/remotes/<remote>/<branch>` present, so the plan's new remote-ref existence check does not change their outcome. The existing `custom_merge warns and makes no change when the remote-tracking branch is absent` test has the local branch present, so it fails DESCENDANT_CHECK before reaching the other-branch path.
- No existing test exercises `require_git_history()` with an uninitialised gitdir volume; the e2e suite always starts the container (initialising the volume) before `merge`/`sync`.
