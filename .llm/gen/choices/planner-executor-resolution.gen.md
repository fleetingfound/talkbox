# Choice: Resolution strategy for planner/executor divergence

Related issue: [planner-executor-divergence](../issues/planner-executor-divergence.gen.md)

## Context

Seven `plan_*` functions in [lib/containers.sh](../../lib/containers.sh) are never called from production code, only from unit tests. They split into two groups with different characteristics:

### Group 1 — lifecycle plans (cleanly fixable)

`plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild`.

These are *incomplete* (they omit the `plan_netbox_populate`/`plan_offbox_populate` step their `run_*` executors perform) and *unused* (the four `run_*_recontain`/`run_*_rebuild` executors inline their own plan assembly). They are pure unconditional command sequences (`commit → rm → [populate] → create → start`), which fits the flat-plan + `execute_plan` model exactly. This mirrors the already-correct onbox lifecycle path (`run_recontain` → `plan_recontain` + `execute_plan`).

### Group 2 — normal-run plans (genuinely divergent)

`plan_onbox_run`, `plan_netbox_run`, `plan_offbox_run`.

These emit a flat `create → start → exec` sequence, but the actual run executors (`run_onbox`/`run_netbox`/`run_offbox`) do substantially more:

- **conditional create-if-not-exists** (reuse an existing container rather than recreating);
- `plan_netbox_populate`/`plan_offbox_populate` and the inheritance `podman commit` (netbox/offbox);
- `ensure_base_image`;
- `podman start` (unconditional, after the conditional create);
- `podman exec` (interactive shell or `-c` command);
- `podman stop -t 1` at session end.

The flat-plan + `execute_plan` model (a single linear array of podman tokens, split on the `podman` keyword) cannot express the conditional create branch without an extension. Forcing the run executors onto `plan_*_run` would either change behaviour (always create fresh, losing container reuse that [SPEC.md §command execution](../../SPEC.md) implies) or require extending the execution model to support conditional commands — a refactor disproportionate to the value.

Most of the run path's *logic* is already unit-pinned through the sub-planners: the create-args builders (`plan_onbox`/`plan_netbox`/`plan_offbox`), the volume-population planners (`plan_netbox_populate`/`plan_offbox_populate`/`plan_volume_populate`) and the inheritance planner (`inherit_source`) all have meaningful unit tests. The only thing the dead `plan_*_run` tests pin is the trivial `create → start → exec` *ordering*, which the e2e suite already covers end to end.

## Options

### Option A — Lifecycle symmetry + delete `plan_*_run` (Recommended)

- Complete and wire the four lifecycle plan functions:
  - add the missing `plan_netbox_populate`/`plan_offbox_populate` calls to `plan_netbox_recontain`/`plan_offbox_recontain`/`plan_netbox_rebuild`/`plan_offbox_rebuild`;
  - rework `run_netbox_recontain`/`run_offbox_recontain`/`run_netbox_rebuild`/`run_offbox_rebuild` to resolve the inheritance source out-of-band (as the onbox executors resolve `ensure_base_image` out-of-band) and then delegate to the corresponding `plan_*` function + `execute_plan`;
  - update [test/unit/lifecycle.bats](../../test/unit/lifecycle.bats) to expect the `run` subcommand (from populate) in the netbox/offbox recontain/rebuild sequences.
- Delete the three `plan_*_run` functions and their unit tests in [test/unit/containers.bats](../../test/unit/containers.bats) and [test/unit/netbox-offbox.bats](../../test/unit/netbox-offbox.bats).
- Normal-run executors keep their current inlined shape; their real logic stays unit-pinned via the sub-planners and behaviour-pinned via e2e.

**Pros:** restores the planner/executor symmetry that the onbox lifecycle path already has, where it is actually achievable; removes genuinely dead code; makes the lifecycle unit tests meaningful (they pin the real executor sequence); no behaviour change; smallest, most targeted change.
**Cons:** loses the (already-false) unit-level pin on the normal-run create→start→exec ordering; accepts that the run executors are e2e-only for their top-level sequencing.

### Option B — Full symmetry (wire all seven)

In addition to Option A's lifecycle work, also wire `run_onbox`/`run_netbox`/`run_offbox` to `plan_onbox_run`/`plan_netbox_run`/`plan_offbox_run` + `execute_plan`. This requires extending the plan/execution model to support the conditional create-if-not-exists branch (e.g. a command-separator token in the plan that the executor treats as a "flush and run only if container missing" boundary, or splitting the run executor into a conditional create-plan + an unconditional start/exec plan).

**Pros:** a single planner/executor discipline across both run and lifecycle paths; retains a unit pin on the normal-run ordering.
**Cons:** the conditional create does not fit the flat-plan model, so this forces a real extension of `execute_plan` (or an awkward split into multiple plan executions); larger refactor; risk of behaviour drift on the well-exercised run path; the gained unit test pins trivial ordering already covered by e2e.

### Option C — Delete all seven `plan_*` functions

Delete all seven unused `plan_*` functions and their unit tests; leave both the run executors and the netbox/offbox lifecycle executors inlined; accept e2e-only coverage for the lifecycle sequencing too.

**Pros:** simplest; removes all dead code in one pass.
**Cons:** loses the lifecycle unit pin (which *is* achievable and meaningful, unlike the run-path one); the onbox lifecycle path keeps its `plan_*`/`run_*` symmetry while the netbox/offbox lifecycle path does not — re-introduces the very asymmetry the issue flags.

## Recommendation

**Option A.** The lifecycle path is where symmetry is achievable and valuable; the run path's conditional logic does not fit the flat-plan model and its real logic is already unit-pinned via sub-planners. This restores meaningful unit coverage where it counts, deletes genuinely dead code, and avoids a disproportionate refactor or behaviour change on the run path.

## Selected option

**Option A (selected by the user).** Complete and wire the four lifecycle plan functions (add missing `plan_*_populate`, wire the four `run_*_recontain`/`run_*_rebuild` executors to their `plan_*` counterparts + `execute_plan`, update the lifecycle unit tests to expect the `run` subcommand). Delete the three `plan_*_run` functions and their unit tests. Normal-run executors keep their current inlined shape; their logic stays unit-pinned via the sub-planners and behaviour-pinned via e2e.

## Related

- [Review: repository review](../reviews/repository-review.gen.md) (shortcoming 1)
- [Choice: planner array-population mechanism](planner-array-mechanism.gen.md)
