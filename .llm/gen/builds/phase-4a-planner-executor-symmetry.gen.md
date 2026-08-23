# Phase 4a: planner/executor lifecycle symmetry + run-plan cleanup

Status: `SUCCESS`

This build implements [phase-4a-planner-executor-symmetry.gen.md](../plans/phase-4a-planner-executor-symmetry.gen.md), which restores the planner/executor symmetry for the netbox/offbox lifecycle verbs by completing the four `plan_*_recontain`/`plan_*_rebuild` functions (adding the missing `plan_netbox_populate`/`plan_offbox_populate` step and the source/dest array parameters), rewiring the four lifecycle executors to delegate to their plan functions via `execute_plan`, and deleting the dead normal-run plan functions (`plan_onbox_run`, `plan_netbox_run`, `plan_offbox_run`); the previously failing netbox/offbox lifecycle unit tests were already committed and now pin the real executor sequence. The related issue [planner-executor-divergence](../issues/planner-executor-divergence.gen.md) is resolved by this phase.

## Overview

- `lib/containers.sh` - the four lifecycle plan functions (`plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild`) gain `_srcs`/`_dsts` array nameref parameters and now append the `plan_netbox_populate`/`plan_offbox_populate` `run` step after `podman rm` and before `podman create` (with `root_source` threaded into the offbox populate calls), so the assembled sequence matches what the executors perform; the four lifecycle executors (`run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild`) now resolve the inheritance source out-of-band (`inherit_source`, plus `ensure_base_image` for the base-source case) and delegate the remainder to the corresponding `plan_*` function + `execute_plan`, retaining the trailing `podman stop -t 1`; `plan_onbox_run`, `plan_netbox_run` and `plan_offbox_run` are deleted.
- Nested planner calls from plan functions now pass the resolved target array name (`"${!_plan_out}"`) so that appending through the shared `_plan_out` nameref does not trigger a circular-name-reference in `plan_gitdir_volume`/`plan_netbox_populate`/`plan_offbox_populate`.

## Verification

- `make test-unit` - exit `0`; 137/137 tests passed (the seven previously-failing netbox/offbox lifecycle plan tests now pass).
- `make test-e2e` - exit `0`; 42/42 tests passed, confirming the external lifecycle behaviour is unchanged.
- `make lint` - exit `0`; ShellCheck clean on all modified scripts.
- `make format` - `shfmt` clean on all modified scripts.
