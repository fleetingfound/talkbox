# Issue: `custom_merge` Case 1 selected over Case 2 when the worktree matches the remote ref but contains host-untracked files

## status

Open.

## summary

When a new file is created and committed inside an `onbox` container (whose working tree is bind-mounted to the host), the file is untracked on the host but its content already matches the container's commit. Running `onbox merge` on the host then fails with git's `error: The following untracked working tree files would be overwritten by merge` instead of applying the spec's Case 2 (`git reset --mixed`), which would advance the branch ref without touching the worktree.

## affected files

- [lib/merge.sh](../../../lib/merge.sh) — `custom_merge_current()` (Case 1 / Case 2 ordering and condition)

## reproduction

1. In a git repository on the host, start `onbox`.
2. Inside the container, create a new file (e.g. `test`), `git add test`, and `git commit`.
3. On the host, the working tree already contains `test` (the working tree is bind-mounted), but it is untracked relative to the host's `HEAD`.
4. Run `onbox merge` on the host.

Result:

```
error: The following untracked working tree files would be overwritten by merge:
        test
Please move or remove them before you merge.
```

## cause

`custom_merge_current()` in [lib/merge.sh](../../../lib/merge.sh) evaluates Case 1 before Case 2:

```sh
if git diff --cached --quiet && git diff --quiet; then
    git merge --ff-only "$remote_ref"        # Case 1
elif git diff --cached --quiet && worktree_matches_tree "$remote_ref"; then
    git reset --mixed "$remote_ref"          # Case 2
else
    ...                                      # Case 3
fi
```

`git diff --quiet` compares the working tree to the index and only considers **tracked** files. A file that was newly added and committed in the container is untracked on the host (the host's `HEAD`/index predate it), so `git diff --quiet` returns success and Case 1 is selected.

Case 1 then runs `git merge --ff-only`, which fast-forwards `HEAD` to the container commit. Because that commit newly tracks `test` and `test` exists as an untracked file in the working tree, git refuses to proceed — even though the untracked file's content is byte-identical to the version being introduced.

In this exact situation the worktree already matches `refs/remotes/<remote>/<branchname>`, so the spec's Case 2 (`git reset --mixed`) is the correct path: it advances the branch ref and index to the remote ref without rewriting the working tree, avoiding the conflict entirely. The implementation never reaches Case 2 because Case 1's condition is satisfied first.

This is the shared-working-tree scenario that `custom_merge()` was specifically designed for (SPEC.md §"`custom_merge()`": "a merge logic which accounts for the fact that the host and container repositories use a shared working tree"), so selecting Case 1 here is a spec deviation.

## why existing tests miss it

- `test/unit/merge.bats` "custom_merge updates the branch when the worktree already matches the remote (Case 2)" only **modifies a tracked file** (`file.txt`) to match the remote, so `git diff --quiet` returns non-zero and Case 2 is reached.
- `test/unit/merge.bats` "custom_merge fast-forwards a current branch with untracked files present (Case 1)" uses an untracked file (`untracked.txt`) that is **not** part of the container commit, so `git merge --ff-only` has nothing to overwrite and succeeds.
- `test/unit/merge.bats` "custom_merge lets git refuse to overwrite a conflicting untracked file (Case 1)" asserts the overwrite refusal is the desired outcome — but that test's worktree does **not** match the remote ref (the untracked `new.txt` has different content from the committed version), so Case 2 does not apply and the refusal is correct there.
- `test/e2e/merge-sync.bats` "onbox merge fast-forwards with an untracked file in the host worktree" likewise uses an untracked file absent from the container commit.

No test exercises the combination: a file that is (a) newly introduced by the container commit and (b) present and matching in the host working tree as an untracked file. That is precisely the `onbox` shared-worktree case.

## suggested fix

Make Case 2 take precedence over Case 1 when the worktree already matches the remote ref, e.g. by reordering the conditions so `worktree_matches_tree` is evaluated first, or by making Case 1 additionally require that the fast-forward would not collide with untracked files (e.g. `git merge --ff-only --no-commit` dry-run, or checking `git status --porcelain` against the set of paths the merge would introduce). The simplest spec-faithful approach is to check Case 2 before Case 1, since `git reset --mixed` is always safe when the worktree already matches the target ref and is a strict subset of Case 1's "clean worktree" situation intersected with "worktree matches remote".

A regression test should cover: container commits a new file `test`; host worktree contains `test` with identical content (untracked); `onbox merge` advances `HEAD` to the container commit without error and without modifying `test`.
