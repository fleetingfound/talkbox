# Plan: Phase 10a — `--init` for persistent containers (PID 1 signal handling)

#flow/redgreen #model/default

## Specification scope

No aspect of `SPEC.md` / `SPEC.gen.md` is altered. This resolves the open
issue [PID 1 (`sleep infinity`) ignores `SIGTERM`](../issues/pid1-sleep-ignores-sigterm.gen.md),
per the selected design in [PID 1 signal handling for persistent containers](../choices/pid1-signal-handling.gen.md)
(Option A — `--init` with `catatonit`). The container's PID 1 process is an
implementation detail not prescribed by the specification.

## To be implemented

- Add the `--init` flag to the argument lists built by the three persistent-
  container planners in [lib/containers.sh](../../../lib/containers.sh):
  - `plan_onbox` (covers `run_onbox`, `plan_recontain`, `plan_rebuild`,
    `plan_rm_container`'s sibling create path — all reuse `plan_onbox`).
  - `plan_netbox` (covers `run_netbox`, `plan_netbox_recontain`,
    `plan_netbox_rebuild`, `create_netbox`).
  - `plan_offbox` (covers `run_offbox`, `plan_offbox_recontain`,
    `plan_offbox_rebuild`, `create_offbox`).
- The flag should be appended in a consistent position relative to the other
  run/create options (e.g. alongside `--userns`/`--network`/`--cap-drop`),
  ahead of the image name and the `sleep infinity` command, so it is treated
  as a `podman create`/`run` option and not as a command argument.
- Podman will inject `catatonit` (its configured default init) as PID 1,
  which reaps zombies and forwards `SIGTERM` to `sleep` (whose default
  disposition as a non-PID-1 process is to terminate). No image or entrypoint
  changes are required.

## To be deferred

- No change to `STOP_GRACE_SECONDS` (currently 5): with `--init` in place it
  becomes a true safety upper bound, consumed only in pathological cases, and
  costs nothing in the common case. A future tuning phase may lower it.
- No preflight check for `catatonit` availability on the host: if the init
  binary is absent, `podman create --init` fails immediately with a clear
  error at create time, which is acceptable. A defensive guard can be added
  later if the dependency proves fragile in practice.
- The one-shot `podman run --rm` containers (`plan_volume_populate`,
  `container_sync_cmd` non-running path) are never `podman stop`'d and do not
  hang; they are deliberately left without `--init`.

## External-facing functionality

Exiting any of `onbox`, `netbox` or `offbox` (and the `--recontain`/
`--rebuild` lifecycle verbs) returns control to the host promptly instead of
incurring the ~5-second hang. `podman stop`'s `SIGTERM` is now honoured by
PID 1 (`catatonit`), which forwards it to `sleep`; the container terminates
immediately rather than blocking for the full grace period before `SIGKILL`.
The grace period remains a safety upper bound only.

## Files to be created

- None.

## Files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — `plan_onbox`,
  `plan_netbox`, `plan_offbox` (the three persistent-container planners).
- [image/entrypoint.sh](../../../image/entrypoint.sh) — to confirm no change
  is needed (the entrypoint's `exec bash -c "$*"` remains; `catatonit` sits
  above it as PID 1).
- [test/unit/containers.bats](../../../test/unit/containers.bats) and
  [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) —
  existing planner unit tests, where `--init` assertions are added.

## Key internal interfaces

- `plan_onbox`, `plan_netbox`, `plan_offbox` — each gains the literal `--init`
  element in its argument list. No signature change. The `run_*`/`create_*`
  executors and the `plan_*_recontain`/`plan_*_rebuild` planners consume these
  lists unchanged and need no modification.

## Tests

Requires tests. The change is a planner-level flag addition, which is
directly unit-testable.

- **Unit tests** (in [test/unit/containers.bats](../../../test/unit/containers.bats)
  and [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats)):
  assert that `plan_onbox`, `plan_netbox` and `plan_offbox` each emit `--init`
  in their argument lists. Also assert that `plan_recontain`/`plan_rebuild`
  (onbox) and `plan_netbox_recontain`/`plan_offbox_recontain`/
  `plan_netbox_rebuild`/`plan_offbox_rebuild` propagate `--init` (since they
  delegate to the base planners). The one-shot `plan_volume_populate` should
  continue to omit `--init`.
- **End-to-end tests:** none required. The full e2e suite must continue to
  pass across all run/lifecycle cases.
