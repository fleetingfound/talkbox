# Tests: Phase 10a — `--init` for persistent containers (PID 1 signal handling)

Linked plan: [phase-10a-pid1-init.gen.md](../plans/phase-10a-pid1-init.gen.md)

Summary: this phase adds red-green unit tests for the plan's single change — appending the literal `--init` flag to the `podman create`/`run` argument lists built by the three persistent-container planners `plan_onbox`, `plan_netbox` and `plan_offbox` in `lib/containers.sh`, so that podman injects `catatonit` as PID 1 (which reaps zombies and forwards `SIGTERM` to `sleep`, eliminating the ~5-second hang on container exit) while the one-shot `plan_volume_populate` helper continues to omit it.

## New tests

Unit tests (per the plan's Test section: "assert that `plan_onbox`, `plan_netbox` and `plan_offbox` each emit `--init` in their argument lists. Also assert that `plan_recontain`/`plan_rebuild` (onbox) and `plan_netbox_recontain`/`plan_offbox_recontain`/`plan_netbox_rebuild`/`plan_offbox_rebuild` propagate `--init` (since they delegate to the base planners). The one-shot `plan_volume_populate` should continue to omit `--init`."):

- `test/unit/containers.bats` — four `plan_onbox` tests:
  - `onbox plan emits --init for the persistent container` — asserts the create-argument array contains the literal `--init` element.
  - `onbox plan emits --init ahead of the image name and the sleep command` — asserts `--init` appears at an index before the image name (the plan's "ahead of the image name and the `sleep infinity` command, so it is treated as a `podman create`/`run` option and not as a command argument").
  - `onbox recontain plan propagates --init to podman create` — asserts `plan_recontain`'s plan array (which embeds the `plan_onbox` create args) contains `--init`.
  - `onbox rebuild plan propagates --init to podman create` — the same through `plan_rebuild`.
- `test/unit/netbox-offbox.bats` — eight tests:
  - `netbox plan emits --init for the persistent container` and `offbox plan emits --init for the persistent container` — assert `plan_netbox`/`plan_offbox` emit the literal `--init` element.
  - `netbox plan emits --init ahead of the image name and the sleep command` and the analogous `offbox` test — assert `--init` precedes the image name in the argument list.
  - `netbox recontain plan propagates --init to podman create` and `offbox recontain plan propagates --init to podman create` — assert `plan_netbox_recontain`/`plan_offbox_recontain` (which embed the base planner create args) contain `--init`.
  - `netbox rebuild plan propagates --init to podman create` and `offbox rebuild plan propagates --init to podman create` — the same through `plan_netbox_rebuild`/`plan_offbox_rebuild`.

Against the current (unimplemented) code all 12 unit tests fail for the correct reason: the three planners emit no `--init` element, so `array_contains '--init'` and the index comparison both fail — none of which is a test-implementation error or timeout.

## Tests edited

- `test/unit/netbox-offbox.bats` — the existing test `volume-population planner runs a no-network helper with the host source read-only` gained the assertion `array_has_none '--init' "${args[@]}"`, asserting the one-shot `plan_volume_populate` continues to omit `--init` exactly as the plan requires ("The one-shot `plan_volume_populate` should continue to omit `--init`"). This is a guard assertion (the helper already omits `--init` today and must keep omitting it after implementation), so the edited test passes both before and after implementation.

## Tests removed

- None. No pre-existing test is inconsistent with the plan: the plan only adds the `--init` flag to the three persistent-container planners and changes no existing behaviour ("No aspect of `SPEC.md` / `SPEC.gen.md` is altered"), and no existing test asserts an exact full argument list or inspects PID 1, so every existing unit and e2e test continues to pass after implementation.
