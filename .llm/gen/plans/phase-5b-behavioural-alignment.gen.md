# Phase 5b: git transport behavioural alignment

#flow/redgreen #model/default

## Scope

Aligns two behavioural aspects of the git transport identified in [git-transport-review](../reviews/git-transport-review.gen.md) (observations 1 and 2), per the user-confirmed choices in [case1-untracked-files](../choices/case1-untracked-files.gen.md) and [merge-sync-failure-behaviour](../choices/merge-sync-failure-behaviour.gen.md).

### Implemented from SPEC.md

Refines the implementation of existing spec aspects:

- `custom_merge()` Case 1 condition — "no staged changes and the worktree is clean relative to `HEAD`" (observation 1).
- `merge` / `sync` `--all` per-branch failure handling (observation 2, spec does not prescribe).

### Deferred

- Error diagnostics (observations 3, 4, 5) are handled in [Phase 5a](phase-5a-error-diagnostics.gen.md).
- Coverage gap filling is handled in [Phase 5c](phase-5c-coverage-gaps.gen.md).

## External-facing functionality

Two user-visible behavioural changes:

- **Case 1 allows untracked files** (observation 1): `onbox merge` / `onbox sync` (and analogues) now fast-forward the current branch when there are no staged changes and no unstaged changes to tracked files, even if untracked files are present in the worktree. Previously, any untracked file caused a warning. If an untracked file conflicts with a file the fast-forward would introduce, `git merge --ff-only` refuses and the user sees git's standard conflict message.

- **`merge --all` stops on first failure** (observation 2): `onbox merge --all` (and analogues) now stops processing at the first branch that fails (non-descendant or dirty worktree), matching `sync --all`'s existing behaviour. Previously, `merge --all` continued to the next branch after a failure and reported overall failure.

## Design

Per [case1-untracked-files](../choices/case1-untracked-files.gen.md) (Option A, confirmed) and [merge-sync-failure-behaviour](../choices/merge-sync-failure-behaviour.gen.md) (Option B, confirmed):

- **Case 1 condition** — replace the `[[ -z "$(git status --porcelain)" ]]` check in `custom_merge_current()` with two checks: `git diff --cached --quiet` (no staged changes) and `git diff --quiet` (no unstaged changes to tracked files). Untracked files no longer prevent Case 1 from firing. The existing `git merge --ff-only` safety guard handles conflicting untracked files.

- **merge failure behaviour** — change `run_merge()`'s per-branch loop from `custom_merge "$container" "$b" || rc=1` (continue, report overall) to stop on the first failure, matching `sync`'s `|| exit 1` semantics. The `rc` accumulator and final `return "$rc"` are replaced by an immediate `return 1` on the first failure.

## Files to create / modify

- Modify `lib/merge.sh` — update `custom_merge_current()` Case 1 condition from `git status --porcelain` emptiness to `git diff --cached --quiet && git diff --quiet`.
- Modify `lib/git.sh` — update `run_merge()` per-branch loop to stop on first failure (return 1 immediately instead of accumulating `rc`).

## Files to read during implementation

- [SPEC.md](../../SPEC.md) §"`custom_merge()`" Case 1.
- [lib/merge.sh](../../lib/merge.sh) — `custom_merge_current()`.
- [lib/git.sh](../../lib/git.sh) — `run_merge()`, `sync_script()`.
- [git-transport-review](../reviews/git-transport-review.gen.md) — observations 1, 2.
- [case1-untracked-files](../choices/case1-untracked-files.gen.md) — selected option A.
- [merge-sync-failure-behaviour](../choices/merge-sync-failure-behaviour.gen.md) — selected option B.

## Key internal interfaces

- `lib/merge.sh`:
  - `custom_merge_current()` — Case 1 condition changes from `[[ -z "$(git status --porcelain)" ]]` to `git diff --cached --quiet && git diff --quiet`. Case 2 and Case 3 conditions are unchanged.
- `lib/git.sh`:
  - `run_merge()` — per-branch loop changes from accumulate-and-continue (`|| rc=1` + `return "$rc"`) to stop-on-first-failure (`|| return 1`). The `rc` local variable is removed.

## Tests

- **Unit tests** (`test/unit/merge.bats`):
  - Case 1 with untracked files present and no staged/tracked changes — fast-forwards successfully (previously warned).
  - Case 1 with untracked files that conflict with the merge result — `git merge --ff-only` fails (git's standard behaviour, no data loss).
  - Existing Case 1 test (clean worktree, no untracked files) — still passes.
  - Existing Case 2 and Case 3 tests — still pass (conditions unchanged).
- **End-to-end tests** (`test/e2e/merge-sync.bats`):
  - `onbox merge` with an untracked file in the host worktree and a clean tracked tree — fast-forwards successfully (previously warned).
  - `onbox merge --all` where one branch is a non-descendant — stops at that branch, subsequent branches are not processed, exit code is non-zero.
  - Existing `merge --all` test (all branches succeed) — still passes.
