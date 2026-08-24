# Dispute: `onbox sync` e2e test expects a fast-forward the plan now refuses (Case 1 untracked-file conflict)

Linked plan: [phase-5b-behavioural-alignment.gen.md](../plans/phase-5b-behavioural-alignment.gen.md)

The pre-existing end-to-end test `onbox sync brings a host commit into the onbox gitdir volume` asserts that `onbox sync` exits 0 when the host has committed a new file. Under the plan's Case 1 change, `custom_merge` now fires Case 1 (whose condition no longer treats untracked files as dirty) and `git merge --ff-only` refuses the fast-forward because the host's newly committed file is untracked from the container repo's perspective and conflicts with a file the fast-forward would introduce. The test's expectation is therefore inconsistent with the plan's explicitly stated behaviour.

## Disputed test

### `onbox sync brings a host commit into the onbox gitdir volume`

- Test file: [test/e2e/merge-sync.bats](../../../test/e2e/merge-sync.bats)
- Failing assertion (line 191): `[[ "$status" -eq 0 ]]` after the `onbox sync` invocation
- Exact failure output:

```
not ok 1 onbox sync brings a host commit into the onbox gitdir volume
# (in test file test/e2e/merge-sync.bats, line 191)
#   `[[ "$status" -eq 0 ]]' failed
# Last output:
# Running as unit: run-p1024655-i1024955.service; invocation ID: ee573b79416c4460b628988ff30d91fb
# From /host/git
#    d9762c4..b434a2d  master     -> host/master
# error: The following untracked working tree files would be overwritten by merge:
# 	hostfile.txt
# Please move or remove them before you merge.
# Aborting
# Updating d9762c4..b434a2d
# Finished with result: exit-code
# Main processes terminated with: code=exited, status=1/FAILURE
```

- Related core files: [lib/merge.sh](../../../lib/merge.sh) (`custom_merge_current()` Case 1), [lib/git.sh](../../../lib/git.sh) (`run_sync()`, `sync_script()`), [lib/containers.sh](../../../lib/containers.sh) (`container_sync_cmd()` — the onbox shared-worktree bind mount)

## Justification

The plan's "External-facing functionality" for Case 1 states (referring to `onbox merge` / `onbox sync` and analogues):

> now fast-forward the current branch when there are no staged changes and no unstaged changes to tracked files, even if untracked files are present in the worktree. Previously, any untracked file caused a warning. If an untracked file conflicts with a file the fast-forward would introduce, `git merge --ff-only` refuses and the user sees git's standard conflict message.

and its "Design" replaces the Case 1 condition with `git diff --cached --quiet` (no staged changes) and `git diff --quiet` (no unstaged changes to tracked files), "Case 2 and Case 3 conditions are unchanged". The implementation in [lib/merge.sh](../../../lib/merge.sh) follows this exactly.

The disputed test performs:

1. `onbox -c --noninteractive 'true'` — the entrypoint initialises the container's git repository in the gitdir volume against the host worktree.
2. A host commit adding a new tracked file `hostfile.txt`.
3. `onbox sync` — `sync_script()` runs `git fetch host` and `custom_merge host <branch>` inside the container's repository.

Because onbox's container repository shares the host worktree (bind-mounted at `/working/<project-base>`, see `plan_onbox`) while its git history lives in a separate gitdir volume, `hostfile.txt` exists in the shared worktree but is **untracked** from the container repo's perspective (the container HEAD predates the host commit). There are no staged changes and no unstaged changes to tracked files, so Case 1 now fires and `git merge --ff-only refs/remotes/host/<branch>` refuses, since the fast-forward would introduce `hostfile.txt` over the untracked file. The user sees git's standard "would be overwritten" refusal — precisely the behaviour the plan describes.

Previously the untracked file blocked Case 1, so the code fell through to Case 2, whose `worktree_matches_tree` helper `git add -A`s the full worktree (including untracked files) and found it already matching the remote tree, then succeeded via `git reset --mixed`. The plan's Case 1 change shadows this Case 2 path for the shared-worktree sync scenario, so the test can no longer pass under the plan's design.

The plan's test planning document ([phase-5b-behavioural-alignment.gen.md](../tests/phase-5b-behavioural-alignment.gen.md)) asserts "No pre-existing test is inconsistent with the plan" and enumerates only the merge-oriented pre-existing tests; it does not consider this sync e2e test. The plan itself requires the new Case 1 behaviour, and the plan explicitly names `onbox sync` as affected, so the test's expectation that `onbox sync` exits 0 in this scenario is inconsistent with the plan document.
