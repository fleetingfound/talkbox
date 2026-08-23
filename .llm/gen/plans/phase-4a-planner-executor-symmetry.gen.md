# Phase 4a: Planner/executor lifecycle symmetry + run-plan cleanup

#flow/redgreen #model/default

Related issue: [planner-executor-divergence](../issues/planner-executor-divergence.gen.md)
Related choice: [planner-executor-resolution](../choices/planner-executor-resolution.gen.md)

## Scope

Resolves the planner/executor divergence by restoring the planner/executor symmetry for the netbox/offbox **lifecycle** path and removing the dead **normal-run** plan functions.

### Implements (from SPEC.md)

No new SPEC behaviour. This phase makes the implementation of the already-specified netbox/offbox lifecycle verbs (`--recontain`, `--rebuild`) faithful to what the executors actually do, and makes the unit suite pin the real executor sequence rather than dead code. Specifically:

- [SPEC.md §image and container management](../../SPEC.md) — the `--recontain`/`--rebuild` verbs and the root-filesystem / read-write volume inheritance they perform.
- [SPEC.md §read-write volume inheritance](../../SPEC.md) — the volume-population step (`plan_netbox_populate`/`plan_offbox_populate`) that the lifecycle plans currently omit.

### Defers

- The normal-run path (`run_onbox`/`run_netbox`/`run_offbox`) is **not** wired to a plan function. The conditional create-if-not-exists logic does not fit the flat-plan + `execute_plan` model; the run path's real logic stays unit-pinned via the sub-planners (`plan_onbox`/`plan_netbox`/`plan_offbox`, `plan_*_populate`, `inherit_source`) and behaviour-pinned via e2e. See the choice doc for rationale.
- Shortcomings 2–6 from the [repository review](../reviews/repository-review.gen.md) (inheritance-argument threading, `--inherit onbox` for offbox volumes, parser generalization for Phase 5, `dest_slug('/')` guard, helper extraction) are out of scope.

## External-facing functionality

No user-visible behaviour change. The netbox/offbox `--recontain`/`--rebuild` verbs continue to perform the same `podman` operations in the same order (`commit → rm → run(populate) → create → start`); only the internal code path that assembles those operations changes.

## Files to create

None.

## Files to read during implementation

- [lib/containers.sh](../../lib/containers.sh) — the four lifecycle plan functions (`plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild`), the four lifecycle executors (`run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild`), the three `plan_*_run` functions to delete, and the onbox lifecycle path (`plan_recontain`/`plan_rebuild` + `run_recontain`/`run_rebuild`) as the symmetry model.
- [test/unit/lifecycle.bats](../../test/unit/lifecycle.bats) — the netbox/offbox recontain/rebuild assertions to update.
- [test/unit/containers.bats](../../test/unit/containers.bats) — the `plan_onbox_run` tests to remove.
- [test/unit/netbox-offbox.bats](../../test/unit/netbox-offbox.bats) — the `plan_netbox_run`/`plan_offbox_run` tests to remove.
- [test/e2e/lifecycle.bats](../../test/e2e/lifecycle.bats) — the end-to-end lifecycle coverage that pins the real executor behaviour.

## Key internal interfaces

### Lifecycle plan completion

`plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild` gain the missing `plan_netbox_populate`/`plan_offbox_populate` call, placed after the `podman rm` and before `podman create`, matching the sequence the corresponding `run_*` executors already perform inline. The populate planner needs the write-mount source/dest arrays, so these four plan functions gain the source/dest array nameref parameters currently held only by the executors (and by `create_netbox`/`create_offbox`). The `root_source` argument is threaded into `plan_offbox_recontain`/`plan_offbox_rebuild` (already passed to `plan_offbox_populate` by the executor).

### Lifecycle executor wiring

`run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild` are reworked to:

1. resolve the inheritance source out-of-band (via `inherit_source`, as today) — this stays in the executor, mirroring how `run_rebuild` keeps `podman build` resolution in the executor and how the onbox executors keep `ensure_base_image` out-of-band;
2. delegate the remainder to the corresponding `plan_*` function + `execute_plan`, instead of inlining the plan assembly;
3. retain the trailing `podman stop -t 1` (as the onbox lifecycle executors do).

### Dead-code removal

`plan_onbox_run`, `plan_netbox_run`, `plan_offbox_run` are deleted from [lib/containers.sh](../../lib/containers.sh).

## Tests

This phase requires tests. The external behaviour is unchanged, but the unit tests are rewritten because they previously pinned dead/incomplete code.

### Unit tests

- **lifecycle.bats** — update the netbox/offbox recontain/rebuild assertions to expect the `run` subcommand (from the populate step) in the sequence, e.g. `commit → rm → run → create → start` (recontain with non-base source) and `build → commit → rm → run → create → start` (rebuild). The base-source recontain case becomes `rm → run → create → start`. Assert the populate `run` targets the worktree volume (and write volumes when present).
- **containers.bats** — remove the two `plan_onbox_run` tests.
- **netbox-offbox.bats** — remove the two `plan_netbox_run`/`plan_offbox_run` tests.
- No new unit tests for the run executors themselves (their logic is already covered by sub-planner unit tests + e2e).

### End-to-end tests

No new e2e tests. The existing [test/e2e/lifecycle.bats](../../test/e2e/lifecycle.bats) coverage of `netbox --recontain`/`offbox --recontain`/`netbox --rebuild`/`offbox --rebuild` must continue to pass unchanged, confirming the external behaviour is preserved.
