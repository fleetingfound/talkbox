# Phase 5c: git transport coverage gaps

#flow/pin #model/default

## Scope

Fills the test coverage gaps identified in [git-transport-review](../reviews/git-transport-review.gen.md) §"coverage gaps". No behaviour change — the tests capture the current behaviour (post-Phase 5a/5b) and must pass against the existing implementation.

### Implemented from SPEC.md

No new spec aspects. Adds test coverage for existing spec behaviour that was previously tested only partially or indirectly.

### Deferred

- Error diagnostics (observations 3, 4, 5) are handled in [Phase 5a](phase-5a-error-diagnostics.gen.md).
- Behavioural alignment (observations 1, 2) is handled in [Phase 5b](phase-5b-behavioural-alignment.gen.md).

## External-facing functionality

None. This phase adds tests only; no user-facing behaviour changes.

## Design

The review identifies two categories of coverage gaps:

### E2e coverage gaps

The following e2e paths are not currently exercised and should be added to `test/e2e/merge-sync.bats` (or a new `test/e2e/sync.bats` if modularisation is preferred):

- **`sync --all`** — e2e only tests default-branch sync. Add a test verifying `onbox sync --all` syncs all host branches into the container's gitdir volume.
- **`sync <branchname>`** — e2e only tests default-branch sync. Add a test verifying `onbox sync <branchname>` syncs the named host branch.
- **`sync` when container is not running** — the existing `onbox sync` test exercises this path incidentally (the container is stopped after `-c --noninteractive true`). Add a test that explicitly asserts the non-running path: create and start the container, stop it, then run `sync` and verify the gitdir volume is updated. This exercises the `container_sync_cmd` temporary-container path directly.
- **`merge --all` creating new local branches** — the unit test covers `custom_merge` creating a new branch directly, but no e2e test exercises it through `run_merge`. Add a test where the container has a branch that doesn't exist on the host, then `merge --all` creates the local branch.

### Unit coverage gaps

The following functions are not directly unit-tested and should be added to `test/unit/git.bats` (or new unit test files if modularisation is preferred):

- **`resolve_branches`** — test with `--all` (enumerates remote branches with a remote argument, host branches without), with a specified branch, and with the default (current branch). Uses a fixture git repository.
- **`sync_script`** — test that the generated script sources the merge module, runs `git fetch host`, and loops over `"$@"` calling `custom_merge host`. This is a pure-output function (prints to stdout), so the test checks the emitted text.
- **`container_sync_cmd`** — test that the command array is assembled correctly for both the running-container path (`podman exec`) and the stopped-container path (`podman run --rm --network=none`). This may require mocking `container_running` and `podman inspect`, or testing via the array output.
- **`execute_fetch_plan`** — test that the plan is split correctly at the `git fetch` boundary, running the podman bundle command first and the host fetch second. This may require mocking `podman run` and `git fetch`, or testing the splitting logic indirectly.
- **`run_sync_in_container`** — covered indirectly via e2e; a unit test would verify it delegates to `container_sync_cmd` and executes the resulting command.

## Files to create / modify

- Modify `test/e2e/merge-sync.bats` (or create `test/e2e/sync.bats`) — add e2e tests for the paths listed above.
- Modify `test/unit/git.bats` (or create `test/unit/git-transport.bats`) — add unit tests for `resolve_branches`, `sync_script`, `container_sync_cmd`, `execute_fetch_plan`, `run_sync_in_container`.

## Files to read during implementation

- [git-transport-review](../reviews/git-transport-review.gen.md) §"coverage gaps".
- [test/e2e/merge-sync.bats](../../test/e2e/merge-sync.bats) — existing e2e test patterns.
- [test/e2e/git-transport.bats](../../test/e2e/git-transport.bats) — existing e2e test patterns for fetch.
- [test/e2e/helpers.bash](../../test/e2e/helpers.bash) — `mk_project`, `mk_talkbox`, `run_talkbox`, `sdrun` helpers.
- [test/unit/merge.bats](../../test/unit/merge.bats) — existing unit test patterns for `custom_merge`.
- [test/unit/git.bats](../../test/unit/git.bats) — existing unit test patterns for `plan_fetch`.
- [test/unit/helpers.bash](../../test/unit/helpers.bash) — `load_lib` helper.
- [lib/git.sh](../../lib/git.sh) — `resolve_branches`, `sync_script`, `run_merge`, `run_sync`, `execute_fetch_plan`.
- [lib/containers.sh](../../lib/containers.sh) — `container_sync_cmd`, `run_sync_in_container`.

## Key internal interfaces

No interfaces are modified. The tests exercise the existing interfaces:

- `resolve_branches <nameref> <all> <branch> [<remote>]` — branch resolution.
- `sync_script` — emits the in-container sync script to stdout.
- `container_sync_cmd <nameref> <project> <container> <script> <branches...>` — assembles the podman command array.
- `execute_fetch_plan <plan...>` — splits and executes the fetch plan.
- `run_sync_in_container <project> <container> <script> <branches...>` — delegates to `container_sync_cmd` and executes.

## Tests

This phase is entirely tests. The tests must pass against the existing implementation (post-Phase 5a/5b if those phases have been implemented).

- **Unit tests**: `resolve_branches`, `sync_script`, `container_sync_cmd`, `execute_fetch_plan`, `run_sync_in_container` — as described above.
- **End-to-end tests**: `sync --all`, `sync <branchname>`, `sync` with stopped container, `merge --all` creating new branches — as described above.
