# Phase 5b: git transport behavioural alignment

Status: `SUCCESS`

This build implements [phase-5b-behavioural-alignment.gen.md](../plans/phase-5b-behavioural-alignment.gen.md), which aligns two behavioural aspects of the git transport per the confirmed choices [case1-untracked-files.gen.md](../choices/case1-untracked-files.gen.md) (Option A) and [merge-sync-failure-behaviour.gen.md](../choices/merge-sync-failure-behaviour.gen.md) (Option B): `custom_merge_current()` Case 1 now fires on `git diff --cached --quiet && git diff --quiet` (allowing untracked files), and `run_merge()` stops at the first failing branch instead of accumulating `rc`. The single disputed pre-existing e2e test, [phase-5b-sync-fast-forward-refusal.gen.md](../disputes/phase-5b-sync-fast-forward-refusal.gen.md), whose expectation that `onbox sync` exits 0 when the host commit adds a new file was inconsistent with the plan's stated Case 1 refusal behaviour, was resolved by the verdict [phase-5b-sync-fast-forward-refusal.gen.md](../verdicts/phase-5b-sync-fast-forward-refusal.gen.md) (test repaired to modify a tracked file instead of adding a new one).

## Overview

- `lib/merge.sh` - `custom_merge_current()` Case 1 condition changed from `[[ -z "$(git status --porcelain)" ]]` to `git diff --cached --quiet && git diff --quiet`; Case 2 and Case 3 conditions unchanged.
- `lib/git.sh` - `run_merge()` per-branch loop changed from `custom_merge "$container" "$b" || rc=1` + `return "$rc"` to `custom_merge "$container" "$b" || return 1`, removing the `rc` accumulator.

## Verification

- `make test-unit` - exit `0`; 153/153 tests passed (including the Case 1 untracked-files unit tests).
- `make test-e2e` - exit `0`; 53/53 tests passed (including the repaired `onbox sync` e2e test and the new `merge --all` stop-on-failure e2e test).
- `shellcheck -x` clean on `lib/merge.sh` and `lib/git.sh`.
