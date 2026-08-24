# Tests: Phase 5b git transport behavioural alignment

Linked plan: [phase-5b-behavioural-alignment.gen.md](../plans/phase-5b-behavioural-alignment.gen.md)

Summary: this phase adds failing tests for the two git-transport behavioural changes from [git-transport-review.gen.md](../reviews/git-transport-review.gen.md) (observations 1 and 2) — Case 1 of `custom_merge_current()` fast-forwards when untracked files are present but there are no staged changes and no unstaged changes to tracked files (per [case1-untracked-files.gen.md](../choices/case1-untracked-files.gen.md) Option A), and `merge --all` stops at the first failing branch like `sync --all` (per [merge-sync-failure-behaviour.gen.md](../choices/merge-sync-failure-behaviour.gen.md) Option B).

The tests pin the following interfaces, which the implementation must provide so that the tests pass once the plan is implemented:

- `lib/merge.sh` `custom_merge_current()` — Case 1 fires when `git diff --cached --quiet && git diff --quiet` (no staged changes and no unstaged tracked changes), i.e. untracked files no longer prevent Case 1; a conflicting untracked file then surfaces as git's own `git merge --ff-only` refusal (no `talkbox:` warning, no data loss).
- `lib/git.sh` `run_merge()` — the per-branch loop stops on the first `custom_merge` failure (immediate return 1) instead of accumulating `rc` and continuing, so with `--all` no branch after the first failing one is processed.

## New tests

Unit tests (`test/unit/merge.bats`, 2 tests added) — built on the same fixture pair (bare `origin.git` and worktree `work`) as the existing `custom_merge` tests:

- `custom_merge fast-forwards a current branch with untracked files present (Case 1)` - with an untracked file in the worktree and no staged or tracked changes, HEAD, the branch ref and the tracked worktree file all advance to the remote commit, the untracked file is left in place, and no `talkbox:` warning is emitted.
- `custom_merge lets git refuse to overwrite a conflicting untracked file (Case 1)` - with an untracked file at a path the fast-forward would introduce, `custom_merge` exits non-zero, HEAD and the untracked file are left unchanged, and the output contains git's standard `would be overwritten` refusal rather than a `talkbox:` warning.

These pin the plan's "Case 1 with untracked files present and no staged/tracked changes — fast-forwards successfully (previously warned)" and "Case 1 with untracked files that conflict with the merge result — `git merge --ff-only` fails (git's standard behaviour, no data loss)", together with [SPEC.md §`custom_merge()`](../../../SPEC.md) Case 1 ("no staged changes and the worktree is clean relative to `HEAD`").

End-to-end tests (`test/e2e/merge-sync.bats`, 2 tests added), run under the existing `systemd-run`-wrapped runner on a temporary git project with a tracked file:

- `onbox merge fast-forwards with an untracked file in the host worktree` - after an in-container empty commit, an untracked file added to the host worktree does not prevent `onbox merge` from fast-forwarding the host branch to the container commit, and the untracked file survives.
- `onbox merge --all stops at the first failing branch and skips the rest` - with a host `feature` branch diverged from its container counterpart (non-descendant), an in-container commit on the current branch and on a `later` branch, `onbox merge --all` exits non-zero with a `talkbox:` warning and leaves `feature`, `later` and the current branch unadvanced, even though the container `later` and current branches are descendants that would otherwise have been merged.

These pin the plan's "`onbox merge` with an untracked file in the host worktree and a clean tracked tree — fast-forwards successfully (previously warned)" and "`onbox merge --all` where one branch is a non-descendant — stops at that branch, subsequent branches are not processed, exit code is non-zero", together with [SPEC.md §merge](../../../SPEC.md).

## Tests edited

None. The two new unit tests and two new end-to-end tests are additions to existing files (`test/unit/merge.bats`, `test/e2e/merge-sync.bats`); no pre-existing test assertion was changed.

## Tests removed

None. No pre-existing test is inconsistent with the plan:

- The existing Case 1 test (`custom_merge fast-forwards a clean current branch (Case 1)`) uses a clean worktree with no untracked files, so the plan's condition change does not alter its outcome — the plan itself requires it to "still pass".
- The existing Case 2 and Case 3 tests use staged or tracked-file changes that `git diff --cached --quiet` / `git diff --quiet` still detect, so the plan's "Case 2 and Case 3 conditions are unchanged" keeps them passing.
- The existing `onbox merge --all applies custom_merge across all onbox branches` e2e test has every branch succeed, so the plan's stop-on-first-failure change does not alter its outcome — the plan requires it to "still pass".
- No existing unit or e2e test asserts that an untracked file blocks Case 1 or that `merge --all` continues after a failure; the plan's changes are therefore unopposed.
