# Verdict: `onbox sync` e2e test expects a fast-forward the plan now refuses

Linked dispute: [phase-5b-sync-fast-forward-refusal.gen.md](../disputes/phase-5b-sync-fast-forward-refusal.gen.md)

Linked plan: [phase-5b-behavioural-alignment.gen.md](../plans/phase-5b-behavioural-alignment.gen.md) — summarised in one sentence: the plan changes `custom_merge_current()` Case 1 to fast-forward when there are no staged changes and no unstaged changes to tracked files (ignoring untracked files), and changes `run_merge --all` to stop on the first failing branch.

No new issue documents were created: the disputed behaviour was entirely a test bug and was resolved during this mediation; the implementation in [lib/merge.sh](../../../lib/merge.sh) already satisfies the SPEC and plan.

## Test: `onbox sync brings a host commit into the onbox gitdir volume`

- Test file: [test/e2e/merge-sync.bats](../../../test/e2e/merge-sync.bats)
- Verdict: `BROKEN_TEST`

### Justification

The test creates a host commit that adds a **new** file `hostfile.txt`, then invokes `onbox sync`. Because the onbox container shares the host worktree via a bind-mount while its git history lives in a separate gitdir volume, `hostfile.txt` is present in the worktree but **untracked** from the container repository's perspective (the container HEAD predates the host commit). There are no staged changes and no unstaged changes to tracked files, so under the plan's revised Case 1 condition `custom_merge_current()` fires Case 1 and runs `git merge --ff-only refs/remotes/host/<branch>`. The fast-forward would introduce `hostfile.txt` as a tracked file, but it already exists in the worktree as an untracked file, so `git merge --ff-only` refuses with git's standard "would be overwritten by merge" message — exactly the behaviour the plan prescribes.

The plan's "External-facing functionality" states:

> `onbox merge` / `onbox sync` (and analogues) now fast-forward the current branch when there are no staged changes and no unstaged changes to tracked files, even if untracked files are present in the worktree. Previously, any untracked file caused a warning. If an untracked file conflicts with a file the fast-forward would introduce, `git merge --ff-only` refuses and the user sees git's standard conflict message.

The plan's "Design" further specifies:

> replace the `[[ -z "$(git status --porcelain)" ]]` check in `custom_merge_current()` with two checks: `git diff --cached --quiet` (no staged changes) and `git diff --quiet` (no unstaged changes to tracked files). Untracked files no longer prevent Case 1 from firing. The existing `git merge --ff-only` safety guard handles conflicting untracked files.

[SPEC.md](../../../SPEC.md) §`custom_merge()` Case 1 defines the condition as "no staged changes and the worktree is clean relative to `HEAD`", which the plan refines to exclude untracked files from the "clean" check. The implementation in [lib/merge.sh](../../../lib/merge.sh) `custom_merge_current()` follows this exactly (`git diff --cached --quiet && git diff --quiet`).

The test's assertion `[[ "$status" -eq 0 ]]` (line 191) expects `onbox sync` to succeed in this scenario, which is inconsistent with the plan's explicitly stated refusal behaviour. The unit test `custom_merge lets git refuse to overwrite a conflicting untracked file (Case 1)` in [test/unit/merge.bats](../../../test/unit/merge.bats) independently pins the same plan behaviour and passes, confirming the implementation is correct.

### Repair

The test's intent is to verify that `onbox sync` brings a host commit into the onbox gitdir volume. The repair changes the host commit from adding a **new** file (`hostfile.txt`) to modifying the existing tracked file (`file.txt`):

```bash
printf 'host-work\n' >"$PROJECT/file.txt"
git -C "$PROJECT" add file.txt
git -C "$PROJECT" commit -q -m host-commit-sync
```

With this change, the shared worktree contains a modification to a **tracked** file (`file.txt`), which `git diff --quiet` detects, so Case 1 does not fire. Case 2 fires instead: the worktree already matches `refs/remotes/host/<branch>` (verified by `worktree_matches_tree`), so `git reset --mixed refs/remotes/host/<branch>` advances the branch ref and index without touching the worktree. The test's assertions (exit 0, gitdir volume branch ref matches host HEAD, `git log --oneline` shows `host-commit-sync`) all hold.

This repair preserves the test's original intent (verifying that sync transfers a host commit with content changes to the container gitdir volume) and exercises the same Case 2 path the test exercised before the plan's Case 1 change (the untracked file previously blocked Case 1 via `git status --porcelain` and fell through to Case 2). The only change is the mechanism by which Case 2 is reached: an unstaged modification to a tracked file rather than an untracked file that no longer blocks Case 1. No assertion is weakened or removed; the commit message, exit-code, ref-equality and `git log` assertions are unchanged.

## Verification

After repair:

- `make test-unit` — `total=153 pass=153 fail=0 skip=0 exit=0`.
- `make test-e2e` — `total=53 pass=53 fail=0 skip=0 exit=0`.

Every remaining failure (none) would be attributable to the project implementation rather than to a test error or timeout.
