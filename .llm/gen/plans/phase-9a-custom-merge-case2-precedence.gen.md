# Phase 9a: Resolve `custom_merge` Case 1 shadowing Case 2

#flow/redgreen #model/default

## Scope

Resolves the open issue [custom_merge Case 1 shadows Case 2 when the worktree matches the remote ref but contains host-untracked files](../issues/custom-merge-case1-shadowing-case2.gen.md).

In the shared-worktree scenario that `custom_merge()` was designed for, a file newly created and committed inside an `onbox` container is bind-mounted into the host working tree, where it is untracked relative to the host's `HEAD`. Running `onbox merge` on the host then fails with git's `error: The following untracked working tree files would be overwritten by merge` instead of applying SPEC.md Case 2 (`git reset --mixed`), which would advance the branch ref without touching the worktree.

### Implemented from SPEC.md

- `custom_merge()` §"`custom_merge()`" Case 2: when the worktree already matches `refs/remotes/<remote>/<branchname>`, advance the current branch with `git reset --mixed` even if the worktree contains untracked files newly introduced by the remote ref.

### Deferred

- Nothing. This is a targeted fix to the existing Case 1 / Case 2 ordering in `custom_merge_current()`.

## External-facing functionality

No change to the `merge` / `sync` subcommand interface. Behavioural change only: `onbox merge` (and `netbox`/`offbox` `merge`, and the in-container `sync`) now succeeds in the shared-worktree case where the host worktree already byte-matches the container commit but the newly-introduced files are untracked on the host. Previously this failed with a raw git overwrite-refusal error.

## Root cause

`custom_merge_current()` in [lib/merge.sh](../../lib/merge.sh) evaluates Case 1 before Case 2. `git diff --quiet` (the Case 1 worktree-clean check) only considers **tracked** files, so a newly-introduced, host-untracked file does not make it fail. Case 1 then runs `git merge --ff-only`, which refuses to overwrite the untracked file even though its content is byte-identical to the version being introduced. Case 2 (`git reset --mixed`, which never touches the worktree) is never reached.

## Design

Reorder the conditionals in `custom_merge_current()` so that **Case 2 is evaluated before Case 1**. `worktree_matches_tree` is the strictest precondition (the worktree tree equals the remote ref's tree) and `git reset --mixed` is always safe when it holds: it advances `HEAD` and the index to the remote ref without rewriting the working tree, so it cannot collide with untracked files. In the overlap where both Case 1 and Case 2 preconditions hold (worktree clean relative to `HEAD` *and* matching the remote), both paths would advance `HEAD` to the remote ref with the same resulting worktree, so preferring Case 2 changes no observable outcome there.

The existing Case 1 tests remain green after the reorder:

- "fast-forwards a clean current branch" — the worktree holds `base` while the remote holds `two`, so `worktree_matches_tree` returns false and Case 1 still fires.
- "fast-forwards with untracked files present" — the untracked file is not part of the container commit, so the worktree tree differs from the remote tree and Case 1 still fires.
- "lets git refuse to overwrite a conflicting untracked file" — the untracked `new.txt` differs in content from the committed version, so the worktree tree differs from the remote tree, Case 2 does not apply, and Case 1's refusal is preserved.

No changes are required to `worktree_matches_tree`, `descendant_check`, or the other-branch path.

## Files to create / modify

- Modify [lib/merge.sh](../../lib/merge.sh) — reorder the `custom_merge_current()` conditionals so the `worktree_matches_tree` (Case 2) branch is evaluated before the `git diff --cached --quiet && git diff --quiet` (Case 1) branch.

## Files to read during implementation

- [SPEC.md](../../SPEC.md) §"`custom_merge()`" (Cases 1–3).
- [lib/merge.sh](../../lib/merge.sh) — `custom_merge_current()` and `worktree_matches_tree()`.
- [test/unit/merge.bats](../../test/unit/merge.bats) — existing Case 1 / Case 2 unit tests.
- [test/e2e/merge-sync.bats](../../test/e2e/merge-sync.bats) — existing `onbox merge` e2e tests, in particular "onbox merge fast-forwards with an untracked file in the host worktree".

## Key internal interfaces

- `custom_merge_current <remote> <branchname>` — unchanged signature; only the order of the two precondition checks inside it changes. Case 2 (`git reset --mixed "$remote_ref"`) is attempted first, then Case 1 (`git merge --ff-only "$remote_ref"`), then Case 3 (warn + return 1). The `git diff --cached --quiet` (no staged changes) guard remains common to both Case 1 and Case 2.

## Tests

- **Unit tests** (`test/unit/merge.bats`): add a regression test that constructs the shared-worktree situation directly against a fixture repository — a commit that newly introduces a file (e.g. `test`) on a throwaway branch pushed to the remote, then on the checked-out branch create `test` in the working tree with identical content as an **untracked** file; assert that `custom_merge origin <branch>` succeeds, advances `HEAD` to the remote ref, leaves `test` unmodified on disk, and emits no `talkbox:` warning. Existing Case 1 / Case 2 / Case 3 tests must continue to pass unchanged, guarding against regressions in the overlap and refusal behaviours.
- **End-to-end tests** (`test/e2e/merge-sync.bats`): add a regression test mirroring the issue's reproduction — inside an `onbox` container, create and commit a new file; on the host (where the file is untracked because the working tree is bind-mounted) run `onbox fetch` then `onbox merge`; assert the merge succeeds, `HEAD` advances to the container commit, and the file is present and unchanged on disk. Run under the existing `systemd-run`-wrapped runner.
