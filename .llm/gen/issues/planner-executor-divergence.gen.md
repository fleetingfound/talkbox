# Issue: planner/executor divergence — netbox/offbox plan functions are unused and incomplete

## Affected files

- [lib/containers.sh](../../../lib/containers.sh) - `plan_onbox_run`, `plan_netbox_run`, `plan_offbox_run`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild`
- [test/unit/containers.bats](../../../test/unit/containers.bats) - `onbox run plan ...` tests
- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) - `netbox/offbox recontain/rebuild plan ...` tests
- [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) - `netbox/offbox run plan ...` tests

## Description

Seven `plan_*` functions in `lib/containers.sh` are never called from production code (`talkbox.sh` or any `lib/*.sh`). They are referenced only by unit tests:

- `plan_onbox_run`, `plan_netbox_run`, `plan_offbox_run`
- `plan_netbox_recontain`, `plan_offbox_recontain`
- `plan_netbox_rebuild`, `plan_offbox_rebuild`

The production executors inline their own plan assembly instead:

- `run_onbox` / `run_netbox` / `run_offbox` call `plan_onbox` / `plan_netbox` / `plan_offbox` (the create-args builders) directly and then run `podman create` / `start` / `exec` by hand, never consulting `plan_*_run`.
- `run_netbox_recontain` / `run_offbox_recontain` / `run_netbox_rebuild` / `run_offbox_rebuild` assemble their own plan arrays (calling `plan_netbox_populate` / `plan_offbox_populate`, `plan_gitdir_volume`, `plan_netbox` / `plan_offbox`, then `execute_plan`) rather than calling the corresponding `plan_*_recontain` / `plan_*_rebuild` functions.

This produces two distinct problems:

1. **Dead-code unit tests.** The unit tests in `test/unit/containers.bats`, `test/unit/lifecycle.bats` and `test/unit/netbox-offbox.bats` pin the output of functions that no production path exercises. The create→start→exec ordering and the commit→rm→create→start sequence they assert are not the sequences the real executors produce.

2. **Plan functions are incomplete.** `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild` and `plan_offbox_rebuild` omit the volume-population step (`plan_netbox_populate` / `plan_offbox_populate`) that their corresponding `run_*` executors perform. If any of these plan functions were wired into `execute_plan` (as the onbox lifecycle functions are), the resulting container would start with empty worktree/write volumes because the host→volume copy never runs. The lifecycle.bats assertions of `$'commit\nrm\ncreate\nstart'` (no `run`) codify the incomplete behaviour, so the tests pass while not reflecting what `run_netbox_recontain` actually does.

Contrast with the onbox lifecycle path, which is consistent: `run_recontain` calls `plan_recontain` + `execute_plan`, `run_rebuild` calls `plan_rebuild` + `execute_plan`, etc. The netbox/offbox equivalents broke this symmetry, and the normal-run path for all three containers never adopted it.

## Suggested fix

Pick one of:

- Have `run_onbox` / `run_netbox` / `run_offbox` call `plan_onbox_run` / `plan_netbox_run` / `plan_offbox_run` + `execute_plan`, and have the netbox/offbox `run_*_recontain` / `run_*_rebuild` call the corresponding `plan_*` functions. Add the missing `plan_netbox_populate` / `plan_offbox_populate` calls to `plan_netbox_recontain` / `plan_offbox_recontain` / `plan_netbox_rebuild` / `plan_offbox_rebuild`, and update the lifecycle.bats assertions to expect the `run` subcommand.
- Or delete the seven unused `plan_*` functions and their unit tests, and accept that the executors are covered only by e2e. This loses the fast unit-level pin on the create/start/exec sequencing.

The first option restores the planner/executor symmetry that the onbox lifecycle path already has and makes the unit tests meaningful.

## Related

- [Review: current repository review](../reviews/repository-review.gen.md)
