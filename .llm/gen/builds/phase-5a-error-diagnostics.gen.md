# Phase 5a: git transport error diagnostics

Status: `SUCCESS`

This build implements [phase-5a-error-diagnostics.gen.md](../plans/phase-5a-error-diagnostics.gen.md), which refines user-facing diagnostics (observations 3, 4 and 5 of [git-transport-review.gen.md](../reviews/git-transport-review.gen.md)) so that three edge cases surface `talkbox:`-formatted messages instead of raw git errors: a detached HEAD with no branch specified to `merge`/`sync`, a non-existent branch name given to `merge` (neither a local nor a remote-tracking ref exists), and an uninitialised gitdir volume passed to `merge`/`sync`. No behaviour change to the merge/sync logic itself.

## Overview

- `lib/git.sh` - `current_branch()` now suppresses the raw `git symbolic-ref` error on a detached HEAD and calls `die` with a `talkbox:`-formatted message; `require_git_history()` now inspects the gitdir volume's mountpoint and calls `die` with a `talkbox:`-formatted message when the volume exists but contains no initialised git repository (no `HEAD` file).
- `lib/merge.sh` - `custom_merge()`'s other-branch path now checks `ref_exists refs/remotes/<remote>/<branchname>` before `git branch -f`, calling `warn` and returning 1 when the remote ref is absent.

## Verification

- `make test-unit` - exit `0`; 151/151 tests passed (including the new detached-HEAD `current_branch` unit test and the non-existent-branch `custom_merge` unit test).
- `make test-e2e` - exit `0`; 51/51 tests passed (including the new `onbox merge <nonexistent-branch>`, detached-host-HEAD `onbox merge`, and uninitialised-gitdir-volume `onbox merge` e2e tests).
- `make lint` - exit `0`; ShellCheck clean on all modified scripts.
- `make format` - `shfmt` clean on all modified scripts.
