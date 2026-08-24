# Tests: Phase 5c git transport coverage gaps

Linked plan: [phase-5c-coverage-gaps.gen.md](../plans/phase-5c-coverage-gaps.gen.md)

Summary: this phase adds the coverage-gap tests identified in [git-transport-review.gen.md](../reviews/git-transport-review.gen.md) §"coverage gaps" — e2e coverage for `sync --all`, `sync <branchname>`, `sync` via the temporary-container path when the container is stopped, and `merge --all` creating new local branches, plus direct unit coverage for `resolve_branches`, `sync_script`, `container_sync_cmd`, `execute_fetch_plan` and `run_sync_in_container`. No behaviour change; every test passes against the existing implementation (post-Phase 5a/5b).

The tests pin the following interfaces, which the existing implementation already provides:

- `lib/git.sh` `resolve_branches()` — with `--all` and a remote argument enumerates `refs/remotes/<remote>/*`; with `--all` and no remote enumerates `refs/heads/*`; with a specified branch returns only that branch; with no branch defaults to the current branch via `current_branch()`.
- `lib/git.sh` `sync_script()` — emits the in-container script that sources `/talkbox/lib/merge.sh`, runs `git fetch host || exit 1`, and loops over `"$@"` calling `custom_merge host "$b" || exit 1`.
- `lib/containers.sh` `container_sync_cmd()` — assembles `podman exec --workdir=/working/<base> <ctr> bash -c "$script" _ <branches...>` when the container is running, and a no-network temporary `podman run --rm --network=none --userns=... --workdir=/working/<base> --entrypoint=/bin/bash` (mounting the gitdir volume at `/working/<base>/.git`, the worktree, `/host/git` read-only and `merge.sh` read-only, then `<image> -c "$script" _ <branches...>`) when it is stopped.
- `lib/git.sh` `execute_fetch_plan()` — splits the plan at the `git fetch` boundary so the podman gitdir-bundle command runs before the host `git fetch`, executing each sub-command in order.
- `lib/containers.sh` `run_sync_in_container()` — delegates to `container_sync_cmd()` and executes the resulting command array.
- The `sync`/`merge` subcommands (`run_sync()`, `run_merge()`) — `sync --all` syncs all host branches into the container gitdir volume, `sync <branchname>` syncs the named host branch, `sync` against a stopped container uses the temporary-container path and leaves the persistent container stopped, and `merge --all` creates new local branches for container-only branches without switching the host checkout.

## New tests

Unit tests (`test/unit/git-transport.bats`, 9 tests) — a new file built on a fixture git repository (a bare `origin.git` and a worktree `work` with a `feature` branch pushed to and fetched from `origin`):

- `resolve_branches with --all and a remote enumerates the remote branches` — with `--all` and `origin` as the remote, the resolved array matches `git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin/` (contains both `feature` and the default branch).
- `resolve_branches with --all and no remote enumerates the host branches` — with `--all` and no remote, the resolved array matches `git for-each-ref --format='%(refname:strip=2)' refs/heads/`.
- `resolve_branches with a specified branch returns only that branch` — with a non-empty `branch` argument the array is exactly that branch.
- `resolve_branches without a branch defaults to the current branch` — with no branch argument the array is exactly `current_branch()`.
- `sync_script emits the in-container sync script text` — the printed script sources `/talkbox/lib/merge.sh`, runs `git fetch host || exit 1`, and contains the `for b in "$@"; do custom_merge host "$b" || exit 1; done` loop.
- `container_sync_cmd assembles a podman exec command for a running container` — with `container_running()` stubbed true, the command array starts `podman exec --workdir=/working/<base> <ctr> bash -c <script> _` and passes the branches as trailing positional arguments.
- `container_sync_cmd assembles a no-network temporary podman run for a stopped container` — with `container_running()` stubbed false, the command array starts `podman run --rm --network=none` with `--entrypoint=/bin/bash`, mounts the gitdir volume at `/working/<base>/.git`, the worktree, `/host/git:ro` and `merge.sh:ro`, and passes `<image> -c <script> _ <branches...>`.
- `execute_fetch_plan splits the plan at the git fetch boundary and runs podman first` — with `podman`/`git` stubbed to log invocations, `execute_fetch_plan` over a `plan_fetch` plan invokes the podman gitdir-bundle command before the host `git fetch ... refs/remotes/onbox`.
- `run_sync_in_container delegates to container_sync_cmd and executes the result` — with `container_sync_cmd` stubbed to record its arguments and emit `touch <marker>`, `run_sync_in_container` records the project/container/script/branches and executes the emitted command (marker created, exit 0).

These pin the plan's `resolve_branches`, `sync_script`, `container_sync_cmd`, `execute_fetch_plan` and `run_sync_in_container` unit-coverage items, together with [SPEC.md §sync](../../../SPEC.md) and [SPEC.md §merge](../../../SPEC.md).

End-to-end tests (`test/e2e/merge-sync.bats`, 4 tests added), run under the existing `systemd-run`-wrapped runner on a temporary git project with a tracked file:

- `onbox sync --all syncs all host branches into the onbox gitdir volume` — after the onbox container and gitdir volume are initialised, a host commit on a new `feature` branch and a commit on the current branch are followed by `onbox sync --all`; the gitdir volume's `refs/heads/<branch>` and `refs/heads/feature` advance to the corresponding host heads.
- `onbox sync <branchname> syncs the named host branch into the onbox gitdir volume` — after a host commit on a `feature` branch, `onbox sync feature` creates the gitdir volume's `refs/heads/feature` at the host's feature head while the host checkout remains on the current branch.
- `onbox sync uses the temporary-container path when the onbox container is stopped` — after initialising the container (which starts and then stops it), the container is asserted stopped; a host commit followed by `onbox sync` advances the gitdir volume branch to the host head and the persistent container remains stopped afterwards (i.e. sync used the temporary-container path, not `podman exec`).
- `onbox merge --all creates new local branches for container-only branches` — after an in-container commit on a branch that does not exist on the host, `onbox fetch` then `onbox merge --all` creates the local branch at the container's commit without switching the host checkout.

These pin the plan's e2e items, together with [SPEC.md §sync](../../../SPEC.md) and [SPEC.md §merge](../../../SPEC.md).

## Tests edited

None. The four new end-to-end tests are additions to `test/e2e/merge-sync.bats`, and the nine new unit tests live in a new `test/unit/git-transport.bats`; no pre-existing test assertion was changed.

## Tests removed

None. No pre-existing test is inconsistent with the implementation:

- The existing `onbox sync` e2e test (default-branch sync with a stopped container) continues to pass unchanged; the new tests add explicit `--all`, named-branch and stopped-container-path assertions without altering it.
- The existing `onbox merge --all applies custom_merge across all onbox branches` e2e test and the existing `custom_merge` unit tests cover branches that already exist or succeed, so the new `merge --all`-creates-branches and `resolve_branches` tests do not conflict with them.
- The existing `plan_fetch` unit tests remain alongside the new `execute_fetch_plan` test in the same module (`git.sh`); no assertion in `test/unit/git.bats` was modified.
