# Review: git transport — `custom_merge()`, `merge` and `sync` subcommands

## scope

This review covers the git-as-transport layer: the `custom_merge()` merge logic in [lib/merge.sh](../../../lib/merge.sh), the `merge` and `sync` subcommand actions (`run_merge` / `run_sync` / `sync_script` / `container_sync_cmd` / `run_sync_in_container`) in [lib/git.sh](../../../lib/git.sh) and [lib/containers.sh](../../../lib/containers.sh), and the supporting branch-resolution helpers (`resolve_branches`, `current_branch`, `remote_branches`, `host_branches`). The `fetch` subcommand is covered insofar as it is reused by `run_merge`.

## summary

The implementation faithfully realises the specification in [SPEC.md](../../../SPEC.md) §"`custom_merge()`", §"merge" and §"sync". All merge operations are fast-forward only, the bundle-based transfer boundary is preserved, and the location-agnostic design of `merge.sh` (sourced both on the host and inside containers) works correctly. The unit suite (149 tests, all passing) and the e2e suite cover the core paths. ShellCheck is clean.

Three minor observations are noted below — none represent incorrect behaviour, but each is an edge case where the user experience could be improved.

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

Case 1 uses `git status --porcelain` being empty, which requires no staged changes, no unstaged changes, **and** no untracked files. The spec says "no staged changes and the worktree is clean relative to `HEAD`". The implementation is therefore slightly stricter than a literal reading (untracked files are treated as dirty), but this is a safe, conservative interpretation — see [observation 1](#observation-1-case-1-treats-untracked-files-as-dirty).

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

1. **Fetch from the container remote.** `plan_fetch` assembles a no-network `podman run` that bundles the gitdir volume (`--all`) into a temp file, followed by a host-side `git fetch <bundle> +refs/heads/*:refs/remotes/<container>/*`. `execute_fetch_plan` splits the plan at the `git fetch` boundary (detecting `git` immediately followed by `fetch`) and runs the podman bundle command first, then the host fetch. The bundle is the only transfer path — no container configs or hooks leak to the host (verified by the e2e test "onbox fetch brings a container commit into the host repo via a bundle without transferring configs or hooks").

2. **Apply `custom_merge` per branch.** `resolve_branches` is called with the container as the remote argument, so `--all` lists `refs/remotes/<container>/*` (the container's branches). Without `--all`, it defaults to the host's current branch or the user-specified branch. `custom_merge "$container" "$b"` is called per branch, continuing on failure (`|| rc=1`) so that one non-descendant branch doesn't block the rest.

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

- **Container not running** → a temporary `--network=none` container mounting the gitdir volume at `/working/<base>/.git`, the worktree (bind-mount for onbox, volume for netbox/offbox) at `/working/<base>`, the host git dir read-only at `/host/git`, and `merge.sh` read-only at `/talkbox/lib/merge.sh`. The entrypoint is bypassed (`--entrypoint=/bin/bash`), but this is safe because the gitdir volume was already initialised by a prior entrypoint run — see [observation 3](#observation-3-require_git_history-does-not-verify-the-git-repo-is-initialised).

Both paths pass the branches as positional args (`"$@"`) to the script via `bash -c "$script" "_" "${branches[@]}"`, correctly avoiding word-splitting issues.

### `execute_fetch_plan` reuse

`run_merge` reuses `plan_fetch` + `execute_fetch_plan` from the `fetch` subcommand. The plan-splitter in `execute_fetch_plan` detects the `git fetch` boundary correctly because the podman command's internal `git bundle create` has `git` followed by `bundle`, not `fetch`. No issue.

## test coverage

### unit — `test/unit/merge.bats` (7 tests, passing)

Covers all `custom_merge` cases:

- Case 1: fast-forward clean current branch.
- Case 2: worktree already matches remote → `git reset --mixed`.
- Case 3: dirty worktree → warn, no change.
- Non-descendant → warn, no change.
- Absent remote-tracking branch (with existing local branch) → warn, no change.
- Create new branch (local head absent) → `git branch -f`, no switch.
- Advance existing non-current branch → `git branch -f`, no switch.

### unit — `test/unit/git.bats` (plan_fetch tests)

Verifies `plan_fetch` emits the no-network gitdir-bundle `podman run` and the `git fetch ... refs/remotes/<container>` command with the correct refspec.

### e2e — `test/e2e/merge-sync.bats` (6 tests)

Covers: `onbox fetch`+`merge`, `merge <branchname>`, `merge --all`, dirty-worktree warning, non-descendant warning, and `onbox sync` (verifying the gitdir volume's branch ref advances to the host HEAD and the in-container `git log` shows the synced commit).

### e2e — `test/e2e/git-transport.bats`

Covers the `fetch` subcommand (bundle transfer, config/hook isolation, `fetch --all` across onbox/netbox/offbox), the host-remote wiring, gitdir-volume freshness, outside-gitdir refusal, and submodule blocking.

### coverage gaps

The following are not covered by any test:

- `netbox merge` / `offbox merge` (e2e tests only exercise `onbox merge`).
- `netbox sync` / `offbox sync`.
- `sync --all` (e2e only tests default-branch sync).
- `sync <branchname>` (explicit non-current branch).
- `sync` when the container is **not** running (the temporary-container path in `container_sync_cmd`). The existing `onbox sync` test runs after `onbox -c --noninteractive true`, which starts and then stops the container, so the sync itself goes through the non-running path — but this is incidental rather than explicitly asserted.
- `merge --all` creating new local branches for container-only branches (the unit test covers this for `custom_merge` directly, but no e2e test exercises it through `run_merge`).
- `resolve_branches`, `sync_script`, `container_sync_cmd`, `run_sync_in_container`, `execute_fetch_plan` — not directly unit-tested; covered only indirectly via e2e.

## observations

These are minor edge-case observations, not bugs. None cause incorrect behaviour (no data loss, no spec violation). Each could be improved for user-friendliness.

### observation 1: Case 1 treats untracked files as dirty

`custom_merge_current` Case 1 uses `[[ -z "$(git status --porcelain)" ]]`, which is empty only when there are no staged changes, no unstaged changes, **and** no untracked files. The spec says "no staged changes and the worktree is clean relative to `HEAD`", which could be read as allowing untracked files (since untracked files are not "relative to HEAD"). The implementation is conservative: an untracked file causes fall-through to Case 2/3, where `worktree_matches_tree` (which `git add -A`s the full worktree including untracked files) will also fail to match, resulting in a warning. This is safe — `git merge --ff-only` would not overwrite an untracked file that doesn't conflict — but a user with harmless untracked files will be warned rather than fast-forwarded.

### observation 2: `merge` continues on branch failure, `sync` stops on first failure

`run_merge` uses `custom_merge "$container" "$b" || rc=1`, continuing to the next branch after a failure. The sync script uses `custom_merge host "$b" || exit 1`, stopping immediately. With `--all`, this means `merge --all` processes every branch and reports overall failure, while `sync --all` stops at the first non-descendant or dirty-worktree branch and skips the rest. The spec does not prescribe either behaviour, so neither is a spec violation, but the asymmetry could surprise users expecting consistent `--all` semantics.

### observation 3: `require_git_history` does not verify the git repo is initialised

`require_git_history` checks `podman volume exists` for the gitdir volume but does not verify that a git repository has been initialised inside it. The gitdir volume is created by `plan_gitdir_volume` (a bare `podman volume create`) and only populated with a git repo by `entrypoint.sh` when the container is first started. If a user were to invoke `merge` or `sync` after the volume was created but before the container was ever started (an unusual sequence, since normal `onbox`/`netbox`/`offbox` invocation always starts the container), the sync script's `git fetch host` would fail with a raw git error rather than a talkbox-formatted message. In normal usage the container is always started before `merge`/`sync` is invoked, so this is theoretical.

### observation 4: detached HEAD causes abrupt exit

When no branch is specified (the default for both `merge` and `sync`), `resolve_branches` calls `current_branch()`, which runs `git symbolic-ref --short HEAD`. On a detached HEAD this fails. Because `talkbox.sh` sets `set -euo pipefail` and the failing assignment `branch="$(current_branch)"` is in the body (not the condition) of an `if` block, the shell exits abruptly with git's raw `fatal: ref HEAD is not a symbolic ref` message rather than a talkbox-formatted error. The exit code is 1, which is appropriate, but the diagnostic is not in the `talkbox:` format. This affects both `merge` and `sync` equally.

### observation 5: DESCENDANT_CHECK passes for non-existent remote ref when local branch is absent

The spec's DESCENDANT_CHECK passes when `refs/heads/<branchname>` does not exist, regardless of whether `refs/remotes/<remote>/<branchname>` exists. If neither ref exists (e.g. the user runs `onbox merge nonexistent`), `custom_merge` reaches `git branch -f "$branchname" "refs/remotes/$remote/$branchname"`, which fails with git's raw `fatal: Not a valid object name` error. The failure is propagated (non-zero exit) so no incorrect changes are made, but the user sees a raw git error rather than a talkbox warning. In practice this only occurs when a user explicitly specifies a non-existent branch name, since `--all` enumerates existing refs and the default uses the current branch (which exists).

## verdict

The git transport implementation is correct, well-structured, and faithfully follows the specification. The merge logic is sound, the bundle-based transfer boundary is preserved, and the location-agnostic design of `merge.sh` is clean. The five observations above are minor edge-case behaviours that could be improved for user-friendliness but do not represent bugs or spec violations.
