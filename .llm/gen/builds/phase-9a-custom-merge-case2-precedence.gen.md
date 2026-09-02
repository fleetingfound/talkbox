# Phase 9a: Resolve `custom_merge` Case 1 shadowing Case 2

Status: `SUCCESS`

This build implements [phase-9a-custom-merge-case2-precedence.gen.md](../plans/phase-9a-custom-merge-case2-precedence.gen.md), which reorders `custom_merge_current()` so the `worktree_matches_tree` (Case 2) branch is evaluated before the clean-worktree (Case 1) branch, resolving [custom-merge-case1-shadowing-case2.gen.md](../issues/custom-merge-case1-shadowing-case2.gen.md) so that `onbox merge` advances `HEAD` via `git reset --mixed` when the host worktree already matches the container commit but contains host-untracked files.

## Overview

- `lib/merge.sh` - in `custom_merge_current()`, the Case 2 branch (`git diff --cached --quiet && worktree_matches_tree "$remote_ref"` → `git reset --mixed`) is now checked before the Case 1 branch (`git diff --cached --quiet && git diff --quiet` → `git merge --ff-only`); Case 3 (warn + return 1) is unchanged.

## Verification

- `make test-unit` - exit `0`; 179/179 tests passed.
- `make test-e2e` - exit `0`; 61/61 tests passed.
- `shellcheck lib/merge.sh` and `shfmt -d lib/merge.sh` - clean.
