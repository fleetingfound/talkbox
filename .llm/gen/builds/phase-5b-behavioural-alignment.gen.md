# Phase 5b: git transport behavioural alignment

Status: `BLOCKED`

This build implements [phase-5b-behavioural-alignment.gen.md](../plans/phase-5b-behavioural-alignment.gen.md), which aligns two behavioural aspects of the git transport per the confirmed choices [case1-untracked-files.gen.md](../choices/case1-untracked-files.gen.md) (Option A) and [merge-sync-failure-behaviour.gen.md](../choices/merge-sync-failure-behaviour.gen.md) (Option B): `custom_merge_current()` Case 1 now fires on `git diff --cached --quiet && git diff --quiet` (allowing untracked files), and `run_merge()` stops at the first failing branch instead of accumulating `rc`. The implementation is blocked by a single disputed pre-existing e2e test, [phase-5b-sync-fast-forward-refusal.gen.md](../disputes/phase-5b-sync-fast-forward-refusal.gen.md), whose expectation that `onbox sync` exits 0 when the host commit adds a new file is inconsistent with the plan's explicitly stated Case 1 refusal behaviour.

## Overview

- `lib/merge.sh` - `custom_merge_current()` Case 1 condition changed from `[[ -z "$(git status --porcelain)" ]]` to `git diff --cached --quiet && git diff --quiet`; Case 2 and Case 3 conditions unchanged.
- `lib/git.sh` - `run_merge()` per-branch loop changed from `custom_merge "$container" "$b" || rc=1` + `return "$rc"` to `custom_merge "$container" "$b" || return 1`, removing the `rc` accumulator.

## Verification

- `make test-unit` - exit `0`; 153/153 tests passed (including the two new Case 1 untracked-files unit tests).
- `make test-e2e` - exit `1`; 52/53 tests passed. The sole failure is the disputed pre-existing test `onbox sync brings a host commit into the onbox gitdir volume` (see dispute document), which the plan's Case 1 change makes inconsistent with the plan.
- `shellcheck -x` clean on `lib/merge.sh` and `lib/git.sh`.
