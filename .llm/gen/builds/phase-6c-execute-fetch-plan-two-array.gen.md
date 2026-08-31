# Phase 6c: Replace `execute_fetch_plan` with two-array `plan_fetch` output

Status: `SUCCESS`

This build implements [phase-6c-execute-fetch-plan-two-array.gen.md](../plans/phase-6c-execute-fetch-plan-two-array.gen.md), which resolves the issue [execute-fetch-plan-brittle-split.gen.md](../issues/execute-fetch-plan-brittle-split.gen.md): the single-flat-array fetch plan and its `git fetch` token-sniffing splitter were replaced with a two-array structure in which the podman gitdir-bundle command and the host `git fetch` command are structurally separate from construction. No external behaviour changes; the fetch and merge subcommands behave exactly as specified in `SPEC.md` §"fetch" and §"merge".

## Overview

- `lib/git.sh` - `plan_fetch` now populates two caller-declared nameref arrays (`<bundle_cmd_array>` then `<fetch_cmd_array>`), building the podman gitdir-bundle command via `gitdir_bundle_cmd` into the first and the host `git fetch` via `host_fetch_cmd` into the second. `execute_fetch_plan` is removed entirely. `run_fetch` declares `bundle_cmd` / `fetch_cmd`, calls `plan_fetch` with both and runs each in turn (`"${bundle_cmd[@]}"` then `"${fetch_cmd[@]}"`), preserving the break-on-failure `rc=1` handling; `run_merge` does the same and preserves the temp-directory cleanup on the failure path.
- `MAP.gen.md` - the `lib/git.sh` description updated: `plan_fetch` assembles the two command arrays run in turn by `run_fetch`, and `run_merge` reuses the same two-array `plan_fetch`; the `execute_fetch_plan` reference was removed.

## Test edits

- `test/unit/git-transport.bats` - the `execute_fetch_plan splits the plan at the git fetch boundary and runs podman first` test was replaced by `plan_fetch fills separate bundle and fetch command arrays with no token leakage`, which calls `plan_fetch` with two arrays and asserts the bundle-command array contains `podman run --rm --network=none` + `git bundle create` + the bundle path, the fetch-command array contains `git fetch` + the bundle + the `refs/remotes/<container>/*` refspec, and that the two arrays are disjoint (element-wise, the only shared token being the incidental `git`). This test could not pass against the new interface and the old one asserted a removed function; the plan requires the replacement verbatim: "replace the `execute_fetch_plan splits the plan at the git fetch boundary` test in [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) with a test that calls `plan_fetch` with two arrays and asserts: (a) the bundle-command array contains `podman run --rm --network=none` + `git bundle create` + the bundle path; (b) the fetch-command array contains `git fetch` + the bundle + the `refs/remotes/<container>/*` refspec; (c) the two arrays are disjoint (no token leakage between them)."
- `test/unit/git.bats` - the two `plan_fetch` tests were updated from the single-array signature `plan_fetch args ...` to the two-array signature `plan_fetch bundle_cmd fetch_cmd ...`, asserting against `bundle_cmd` for the podman bundle command and `fetch_cmd` for the host fetch. The old calls were misaligned with the new interface and could not pass; the plan requires it: "Update any `plan_fetch` assertions in [test/unit/git.bats](../../../test/unit/git.bats) for the new two-array signature." The remaining `resolve_branches` / `sync_script` / `container_sync_cmd` / `run_sync_in_container` tests are unaffected, as the plan states.

## Verification

- `make test-unit` - exit `0`; 162/162 tests passed (including the replaced `git-transport.bats` case and the updated `git.bats` cases).
- `make test-e2e` - exit `0`; 57/57 tests passed unchanged, confirming the refactor preserves external fetch/merge behaviour.
- `make lint` clean; `shfmt` reports no formatting changes on the edited scripts.
