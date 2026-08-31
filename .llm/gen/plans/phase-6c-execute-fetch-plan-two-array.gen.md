# Plan: Phase 6c — Replace `execute_fetch_plan` with two-array `plan_fetch` output

#flow/unified #model/default

## Specification scope

No aspect of `SPEC.md` / `SPEC.gen.md` is altered and no external behaviour changes. This resolves the open issue [`execute_fetch_plan` boundary splitting is brittle](../issues/execute-fetch-plan-brittle-split.gen.md), per the selected design in [`execute_fetch_plan` boundary mechanism](../choices/execute-fetch-plan-boundary.gen.md) (Option A — two-array output). The fetch and merge subcommands continue to behave exactly as specified in [SPEC.md](../../../SPEC.md) §"fetch" and §"merge".

## To be implemented

Replace the single-flat-array + implicit-boundary-splitter design in [lib/git.sh](../../../lib/git.sh) with a two-array structure that makes the two commands (podman bundle, host git fetch) structurally separate from construction:

- Change `plan_fetch` to populate two caller-declared arrays instead of one: one for the no-network `podman run` gitdir-bundle command (currently built by `gitdir_bundle_cmd`) and one for the host-side `git fetch` command (currently built by `host_fetch_cmd`). The two `*_cmd` helpers already build into a nameref array, so `plan_fetch` calls each into a separate caller-supplied array.
- Remove `execute_fetch_plan` entirely. Its sole purpose was to split the flattened plan at the `git fetch` boundary; with two arrays there is no boundary to detect.
- Update `run_fetch` to declare two local arrays, call `plan_fetch` with both, and run each command array in turn (`"${bundle_cmd[@]}"` then `"${fetch_cmd[@]}"`), preserving the existing error-handling (break on fetch-plan failure, `rc=1`).
- Update `run_merge` analogously: declare two arrays, call `plan_fetch`, run the bundle command then the fetch command, then proceed to `custom_merge` per branch as today. Preserve the temp-directory cleanup on the failure path.

## To be deferred

- Nothing. This is a self-contained internal refactor of the fetch-plan mechanism.

## External-facing functionality

None — `onbox fetch`, `netbox fetch`, `offbox fetch`, `fetch --all`, `onbox merge`, `netbox merge`, `offbox merge` all continue to behave identically from the user's perspective.

## Files to be created

- None.

## Files to read during implementation

- [lib/git.sh](../../../lib/git.sh) — `plan_fetch`, `execute_fetch_plan`, `gitdir_bundle_cmd`, `host_fetch_cmd`, `run_fetch`, `run_merge`.
- [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) — the `execute_fetch_plan splits the plan at the git fetch boundary` test (to be replaced) and the `plan_fetch`-related assertions in [test/unit/git.bats](../../../test/unit/git.bats).
- [MAP.gen.md](../../../MAP.gen.md) — `lib/git.sh` description references `plan_fetch` / `execute_fetch_plan`.

## Key internal interfaces

- `plan_fetch <bundle_cmd_array> <fetch_cmd_array> <project> <container> <bundle>` — populates two caller-declared arrays: the podman gitdir-bundle command and the host `git fetch` command.
- `execute_fetch_plan` — removed.
- `run_fetch` / `run_merge` — call `plan_fetch` with two arrays and run each in turn.

## Tests

The test edits and implementation edits are inseparable here (the existing unit test asserts the old `execute_fetch_plan` splitting behaviour and the single-array `plan_fetch` shape; it cannot pass against the new two-array interface), so the whole phase is implemented by a single agent.

- **Unit tests:** replace the `execute_fetch_plan splits the plan at the git fetch boundary` test in [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) with a test that calls `plan_fetch` with two arrays and asserts: (a) the bundle-command array contains `podman run --rm --network=none` + `git bundle create` + the bundle path; (b) the fetch-command array contains `git fetch` + the bundle + the `refs/remotes/<container>/*` refspec; (c) the two arrays are disjoint (no token leakage between them). Update any `plan_fetch` assertions in [test/unit/git.bats](../../../test/unit/git.bats) for the new two-array signature. The remaining `resolve_branches` / `sync_script` / `container_sync_cmd` / `run_sync_in_container` tests are unaffected.
- **End-to-end tests:** no e2e changes; the fetch and merge e2e suites ([test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats), [test/e2e/merge-sync.bats](../../../test/e2e/merge-sync.bats)) exercise the real fetch/merge path and must continue to pass unchanged, confirming the refactor preserves external behaviour.
