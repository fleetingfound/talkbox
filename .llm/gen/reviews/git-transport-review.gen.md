# Review: git transport — `custom_merge()`, `merge` and `sync` subcommands

## scope

This review covers the git-as-transport layer: the `custom_merge()` merge logic in [lib/merge.sh](../../../lib/merge.sh), the `merge` and `sync` subcommand actions (`run_merge` / `run_sync` / `sync_script` / `container_sync_cmd` / `run_sync_in_container`) in [lib/git.sh](../../../lib/git.sh) and [lib/containers.sh](../../../lib/containers.sh), and the supporting branch-resolution helpers (`resolve_branches`, `current_branch`, `remote_branches`, `host_branches`). The `fetch` subcommand is covered insofar as it is reused by `run_merge`.

## summary

The implementation faithfully realises the specification in [SPEC.md](../../../SPEC.md) §"`custom_merge()`", §"merge" and §"sync". All merge operations are fast-forward only, the bundle-based transfer boundary is preserved, and the location-agnostic design of `merge.sh` (sourced both on the host and inside containers) works correctly. The unit suite (170 tests, all passing) and the e2e suite (60 tests, all passing) cover the core paths. ShellCheck is clean.

This review was originally written when the suite had 149 unit tests and five edge-case observations. All five observations have since been resolved in the implementation and are now backed by dedicated unit and e2e tests (see [observations](#observations) below for the resolution details).

## `custom_merge()` — `lib/merge.sh`

### DESCENDANT_CHECK

`descendant_check()` implements the spec exactly:

- `refs/heads/<branchname>` absent → pass (return 0).
- present but `refs/remotes/<remote>/<branchname>` absent → fail (return 1).
- both present → `git merge-base --is-ancestor` (remote is a descendant of head).

On failure, `custom_merge()` warns (`talkbox: refusing to merge ...`) and returns 1, making no changes. Correct.

### current branch — Cases 1–3

`custom_merge_current()` implements the three cases in spec order:

| Case | Condition (implementation) | Action | Spec match |
|------|---------------------------|--------|------------|
| 1 | `git status --porcelain` is empty | `git merge --ff-only` | ✓ |
| 2 | `git diff --cached --quiet` **and** `worktree_matches_tree` | `git reset --mixed` | ✓ |
| 3 | neither | warn + return 1 | ✓ |

Case 1 uses `git diff --cached --quiet && git diff --quiet`, which checks for no staged changes and no unstaged **tracked** changes. Untracked files do not cause either `git diff` check to fail, so Case 1 now fast-forwards even with untracked files present — matching the spec's "no staged changes and the worktree is clean relative to `HEAD`" reading. `git merge --ff-only` itself refuses to overwrite a conflicting untracked file, so the safety property is preserved by git. This is covered by the unit tests "custom_merge fast-forwards a current branch with untracked files present (Case 1)" and "custom_merge lets git refuse to overwrite a conflicting untracked file (Case 1)", and the e2e test "onbox merge fast-forwards with an untracked file in the host worktree". See [observation 1](#observation-1-case-1-now-fast-forwards-with-untracked-files-resolved) (resolved).

> **Update (2026-09-02):** observation 1's resolution is incomplete. When the container commit **introduces a new file** that is already present (and matching) in the host worktree as an untracked file — the canonical `onbox` shared-worktree situation — Case 1 is selected (because `git diff --quiet` ignores untracked files) and `git merge --ff-only` fails with `error: The following untracked working tree files would be overwritten by merge`, even though the worktree already matches the remote ref and Case 2 (`git reset --mixed`) would succeed without touching the worktree. The existing Case 2 tests only modify a *tracked* file, and the existing Case 1 untracked-file tests only use untracked files that are *absent* from the container commit, so neither covers this combination. See the open issue [custom-merge-case1-shadowing-case2](../issues/custom-merge-case1-shadowing-case2.gen.md).

Case 2's `git diff --cached --quiet` correctly checks "no staged changes", and `worktree_matches_tree` correctly checks "the worktree already matches `refs/remotes/<remote>/<branchname>`" by building a throwaway tree from the worktree via a temporary `GIT_INDEX_FILE` and comparing it to `ref^{tree}`. The temp index is cleaned up on all paths. The real index is never disturbed. Correct.

### other branch

`git branch -f "$branchname" "refs/remotes/$remote/$branchname"` advances (or creates) the branch ref without switching. Since DESCENDANT_CHECK guarantees the remote ref is a descendant of the existing head ref (or the head ref doesn't exist), this is a fast-forward of the branch pointer. Correct.

### `worktree_matches_tree()`

The temp-index pattern is sound:

1. `mktemp` a path, then `rm -f` it so git creates a fresh index at that path.
2. `GIT_INDEX_FILE=<tmp> git add -A` — stages the entire worktree into the temp index without touching the real index.
3. `GIT_INDEX_FILE=<tmp> git write-tree` — materialises the tree hash.
4. Compare to `git rev-parse "$ref^{tree}"`.

Cleanup (`rm -f "$tmp_index"`) happens before the `remote_tree` lookup, so the temp file is always removed even if `git rev-parse` fails. Correct.

### self-containment

`merge.sh` defines its own `warn()` rather than relying on `common.sh`'s `die()`. This is intentional and correct: the file is bind-mounted read-only at `/talkbox/lib/merge.sh` inside containers and `source`d by the sync script, where `common.sh` is not available. The `warn()` format (`talkbox: <message>`) matches `die()`'s prefix, keeping user-facing output consistent.

## `merge` subcommand — `run_merge()`

The flow matches the spec's two steps:

1. **Fetch from the container remote.** `plan_fetch` fills two separate arrays: `bundle_cmd` (a no-network `podman run` that bundles the gitdir volume with `git bundle create --all` into a temp file) and `fetch_cmd` (the host-side `git fetch <bundle> +refs/heads/*:refs/remotes/<container>/*`). `run_merge` runs `bundle_cmd` then `fetch_cmd` directly. The bundle is the only transfer path — no container configs or hooks leak to the host (verified by the e2e test "onbox fetch brings a container commit into the host repo via a bundle without transferring configs or hooks").

2. **Apply `custom_merge` per branch.** `resolve_branches` is called with the container as the remote argument, so `--all` lists `refs/remotes/<container>/*` (the container's branches). Without `--all`, it defaults to the host's current branch or the user-specified branch. `custom_merge "$container" "$b"` is called per branch, stopping on the first failure (`|| return 1`) so that one non-descendant or dirty-worktree branch aborts the remaining branches.

Temp-directory cleanup is handled on both success and fetch-failure paths. Correct.

## `sync` subcommand — `run_sync()` / `sync_script()` / `container_sync_cmd()`

The flow matches the spec's two steps, executed inside the container's repository:

1. **Fetch from the host remote.** The generated script runs `git fetch host`, which fetches from `/host/git/` (the read-only bind-mount of the host's git dir) into `refs/remotes/host/*`.

2. **Apply `custom_merge` per branch.** The script loops over the resolved branches and calls `custom_merge host "$b"`.

### branch resolution

`resolve_branches` is called **without** a remote argument, so `--all` lists host branches (`refs/heads/*`) rather than remote branches. This is correct per the spec: "applies `custom_merge host <branchname>` to all **host** branches". Without `--all`, the host's current branch is used. The branches are resolved on the host and passed as positional arguments to the in-container script.

### execution venue — `container_sync_cmd()`

Two paths:

- **Container running** → `podman exec --workdir=/working/<base> <ctr> bash -c "$script" _ <branches...>`. The `host` remote and `core.worktree` are already configured in the gitdir volume from the entrypoint's initial run. The `/host/git/` bind-mount reflects the current host git state (including new commits made since container creation).

- **Container not running** → a temporary `--network=none` container mounting the gitdir volume at `/working/<base>/.git`, the worktree (bind-mount for onbox, volume for netbox/offbox) at `/working/<base>`, the host git dir read-only at `/host/git`, and `merge.sh` read-only at `/talkbox/lib/merge.sh`. The entrypoint is bypassed (`--entrypoint=/bin/bash`); `require_git_history` verifies the gitdir volume has been initialised (`$mountpoint/HEAD` exists) before this path is taken, so the in-container `git fetch host` operates on a real repository.

Both paths pass the branches as positional args (`"$@"`) to the script via `bash -c "$script" "_" "${branches[@]}"`, correctly avoiding word-splitting issues.

### `plan_fetch` reuse

`run_merge` reuses the same `plan_fetch` helper as the `fetch` subcommand, filling separate `bundle_cmd` and `fetch_cmd` arrays. This two-array design replaced the earlier single-array `execute_fetch_plan` splitter that was flagged as brittle (see the resolved issue [execute-fetch-plan-brittle-split](../issues/execute-fetch-plan-brittle-split.gen.md)). No issue.

## test coverage

### unit — `test/unit/merge.bats` (11 tests, passing)

Covers all `custom_merge` cases:

- Case 1: fast-forward clean current branch.
- Case 1: fast-forward with untracked files present.
- Case 1: git refuses to overwrite a conflicting untracked file.
- Case 2: worktree already matches remote → `git reset --mixed`.
- Case 3: dirty worktree → warn, no change.
- Non-descendant → warn, no change.
- Absent remote-tracking branch (with existing local branch) → warn, no change.
- Create new branch (local head absent) → `git branch -f`, no switch.
- Advance existing non-current branch → `git branch -f`, no switch.
- Neither local nor remote branch exists → warn, no change.

### unit — `test/unit/git.bats` (plan_fetch tests)

Verifies `plan_fetch` emits the no-network gitdir-bundle `podman run` and the `git fetch ... refs/remotes/<container>` command with the correct refspec.

### e2e — `test/e2e/merge-sync.bats` (14 tests)

Covers: `onbox fetch`+`merge`, `merge <branchname>`, `merge --all`, fast-forward with an untracked file, `merge --all` stopping at the first failing branch, dirty-worktree warning, non-descendant warning, non-existent-branch warning, detached-HEAD error, uninitialised-gitdir-volume error, `onbox sync` (default branch), `onbox sync --all`, `onbox sync <branchname>`, `onbox sync` via the temporary-container path when the onbox container is stopped, and `merge --all` creating new local branches for container-only branches.

### e2e — `test/e2e/git-transport.bats`

Covers the `fetch` subcommand (bundle transfer, config/hook isolation, `fetch --all` across onbox/netbox/offbox), the host-remote wiring, gitdir-volume freshness, outside-gitdir refusal, and submodule blocking.

### coverage gaps

The following are not covered by any test:

- `netbox merge` / `offbox merge` (e2e tests only exercise `onbox merge`).
- `netbox sync` / `offbox sync`.
- `sync --all` is now covered (e2e test "onbox sync --all syncs all host branches into the onbox gitdir volume").
- `sync <branchname>` is now covered (e2e test "onbox sync <branchname> syncs the named host branch into the onbox gitdir volume").
- `sync` when the container is **not** running is now explicitly covered (e2e test "onbox sync uses the temporary-container path when the onbox container is stopped").
- `merge --all` creating new local branches for container-only branches is now covered (e2e test "onbox merge --all creates new local branches for container-only branches").
- `resolve_branches`, `sync_script`, `container_sync_cmd`, `run_sync_in_container` are now directly unit-tested in `test/unit/git-transport.bats`.
- `execute_fetch_plan` is exercised indirectly via e2e `fetch` and `merge` tests; it is no longer present as a separate function (the two-array `plan_fetch` design replaced the brittle single-array splitter, per the resolved issue [execute-fetch-plan-brittle-split](../issues/execute-fetch-plan-brittle-split.gen.md)).

## observations

All five observations from the original review have been resolved in the current implementation. Each is documented below together with the resolution and the test that now guards it.

### observation 1: Case 1 now fast-forwards with untracked files (resolved)

The original observation noted that Case 1 used `git status --porcelain` (empty only when there are also no untracked files), causing a fall-through to Case 2/3 with harmless untracked files. The implementation now uses `git diff --cached --quiet && git diff --quiet`, which does not consider untracked files. Case 1 now fast-forwards in the presence of untracked files, while `git merge --ff-only` retains the safety guarantee that a conflicting untracked file is not overwritten. Covered by unit tests `test/unit/merge.bats` ("fast-forwards a current branch with untracked files present", "lets git refuse to overwrite a conflicting untracked file") and e2e test `test/e2e/merge-sync.bats` ("onbox merge fast-forwards with an untracked file in the host worktree").

### observation 2: `merge` and `sync` now both stop on first branch failure (resolved)

The original observation noted an asymmetry: `run_merge` used `custom_merge ... || rc=1` (continue on failure) while the sync script used `|| exit 1` (stop on failure). `run_merge` now uses `custom_merge "$container" "$b" || return 1`, so both `merge --all` and `sync --all` stop at the first non-descendant or dirty-worktree branch. The behaviour is now symmetric. Covered by the e2e test "onbox merge --all stops at the first failing branch and skips the rest".

### observation 3: `require_git_history` now verifies the git repository is initialised (resolved)

The original observation noted that `require_git_history` checked only `podman volume exists` for the gitdir volume. It now additionally inspects the volume mountpoint via `podman volume inspect --format '{{.Mountpoint}}'` and requires `$mountpoint/HEAD` to exist, dying with `talkbox: no git history in the $container gitdir volume; start the container first` when the volume exists but has not been initialised by the entrypoint. Covered by the e2e test "onbox merge on an uninitialised gitdir volume errors with a talkbox message".

### observation 4: detached HEAD now produces a talkbox-formatted error (resolved)

The original observation noted that `current_branch()` ran `git symbolic-ref --short HEAD` whose failure under `set -euo pipefail` produced git's raw `fatal: ref HEAD is not a symbolic ref` message. `current_branch()` now runs `git symbolic-ref --short HEAD 2>/dev/null || die "cannot determine the current branch: HEAD is detached" 1`, producing a `talkbox:`-prefixed message. Covered by the unit test "current_branch on a detached HEAD produces a talkbox error" and the e2e test "onbox merge with a detached host HEAD errors with a talkbox message and exits non-zero".

### observation 5: non-existent remote branch now warned with a talkbox message (resolved)

The original observation noted that when neither `refs/heads/<branchname>` nor `refs/remotes/<remote>/<branchname>` exists, DESCENDANT_CHECK passes and `git branch -f` fails with git's raw `fatal: Not a valid object name` error. `custom_merge` now guards the other-branch path with `if ! ref_exists "refs/remotes/$remote/$branchname"; then warn "refusing to merge $branchname from $remote: the remote branch does not exist"; return 1; fi` before `git branch -f`. Covered by the unit test "custom_merge warns and creates nothing when neither local nor remote branch exists" and the e2e test "onbox merge <nonexistent-branch> warns with a talkbox message and exits non-zero".

## verdict

The git transport implementation is correct, well-structured, and faithfully follows the specification. The merge logic is sound, the bundle-based transfer boundary is preserved, and the location-agnostic design of `merge.sh` is clean. All five observations from the original review have been resolved, each backed by dedicated unit and e2e tests.

One subsequent issue was found: Case 1 shadows Case 2 in the `onbox` shared-worktree scenario where the container introduces a new file that already exists (matching) as an untracked file on the host — see the open issue [custom-merge-case1-shadowing-case2](../issues/custom-merge-case1-shadowing-case2.gen.md).
