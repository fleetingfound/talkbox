# Tests: Phase 11a — Entrypoint readiness synchronization (tmpfs sentinel)

Linked plan: [phase-11a-entrypoint-readiness-sync.gen.md](../plans/phase-11a-entrypoint-readiness-sync.gen.md)

Linked issue: [e2e-fresh-container-exec-races-entrypoint.gen.md](../issues/e2e-fresh-container-exec-races-entrypoint.gen.md)

Summary: this phase adds red-green tests for the plan's readiness-synchronization design (Option A — tmpfs sentinel), in which the three persistent-container planners `plan_onbox`, `plan_netbox` and `plan_offbox` gain the literal `--tmpfs` `/run/talkbox` create options, `image/entrypoint.sh` writes a `/run/talkbox/ready` sentinel as its final pre-`exec` action, and the `run_onbox`/`run_netbox`/`run_offbox` executors wait for that sentinel via a new bounded `podman exec` polling helper (`wait_for_entrypoint`) before running the user command, so commands in a freshly started container no longer race the entrypoint's start-up work.

## New tests

Unit tests (per the plan's Test section: "assert that `plan_onbox`, `plan_netbox` and `plan_offbox` each emit `--tmpfs` and `/run/talkbox` in their argument lists... plan_recontain/plan_rebuild (onbox) and the netbox/offbox recontain/rebuild planners propagate `--tmpfs` (since they delegate to the base planners). The one-shot `plan_volume_populate` should continue to omit `--tmpfs`"):

- `test/unit/containers.bats` — five tests:
  - `onbox plan mounts a tmpfs at /run/talkbox for the entrypoint readiness sentinel` — asserts the create-argument array contains the literal `--tmpfs` element immediately followed by `/run/talkbox`, at an index ahead of the image name (so it is a `podman create` option rather than a command argument).
  - `onbox recontain plan propagates the /run/talkbox tmpfs to podman create` and `onbox rebuild plan propagates the /run/talkbox tmpfs to podman create` — assert `plan_recontain`/`plan_rebuild` (which embed the `plan_onbox` create args) contain both elements.
  - `wait_for_entrypoint returns success once podman exec reports the sentinel file` — sources the containers library with a fake `podman` (exits 0) on `PATH` and asserts `wait_for_entrypoint <ctr>` returns success after issuing a single `podman exec` whose command line references `/run/talkbox/ready`, per the plan's key interface ("a new readiness-wait helper in `lib/containers.sh` (e.g. `wait_for_entrypoint <ctr>`) that runs a bounded `podman exec` poll for `/run/talkbox/ready`").
  - `wait_for_entrypoint dies with a talkbox error when the sentinel never appears` — with a fake `podman` that exits 1 (simulating an exhausted in-container poll), asserts the helper exits nonzero printing a `talkbox:` error, per the plan ("If the timeout expires, the helper should call `die` with a descriptive message").
- `test/unit/netbox-offbox.bats` — six tests:
  - `netbox plan mounts a tmpfs at /run/talkbox...` and `offbox plan mounts a tmpfs at /run/talkbox...` — assert `plan_netbox`/`plan_offbox` emit the literal `--tmpfs` `/run/talkbox` pair ahead of the image name.
  - `netbox recontain plan propagates...`, `offbox recontain plan propagates...`, `netbox rebuild plan propagates...`, `offbox rebuild plan propagates...` — the same presence assertions through `plan_netbox_recontain`/`plan_offbox_recontain`/`plan_netbox_rebuild`/`plan_offbox_rebuild`.

End-to-end test (per the plan: "an e2e test that verifies a git command succeeds immediately after container start (without a prior warm-up call) would directly exercise the fix and guard against regression"):

- `test/e2e/git-identity.bats` — `a git command in a freshly started container runs only after the entrypoint readiness sentinel appears`: drives `onbox -c --noninteractive "git log --format=%s -1 && echo GIT-SUCCEEDED"` in a freshly started container with a passthrough logging `podman` shim on `PATH` (all podman calls delegated to the real binary), then asserts the git command succeeded and that the podman invocation log shows a `podman exec` polling for `/run/talkbox/ready` at a line before the user-command exec — i.e. the executor waited for the sentinel between `podman start` and the user-command `podman exec`, exactly as the plan's "Call the readiness-wait helper in `run_onbox`, `run_netbox` and `run_offbox`, after `podman start` and before the user-command `podman exec`" requires. The test exercises the onbox path; netbox/offbox share the identical executor structure and are covered by the unit planner tests (their existing e2e tests continue to run git commands in freshly started containers).

Against the current (unimplemented) code all 11 new unit tests and the new e2e test fail for the correct reason: the three planners emit no `--tmpfs`/`/run/talkbox` elements, `wait_for_entrypoint` is not defined (so no readiness `podman exec` appears in the e2e podman log), and none of the failures is a test-implementation error or timeout.

## Tests edited

- `test/unit/netbox-offbox.bats` — the existing test `volume-population planner runs a no-network helper with the host source read-only` gained the assertion `array_has_none '--tmpfs' "${args[@]}"` alongside its existing `--init` guard, asserting the one-shot `plan_volume_populate` continues to omit `--tmpfs` exactly as the plan requires ("The one-shot `plan_volume_populate` should continue to omit `--tmpfs`" and, in the plan's deferral list, one-shot `podman run --rm` containers "do not use `podman exec`... so no race exists"). This is a guard assertion (the helper already omits `--tmpfs` today and must keep omitting it after implementation), so the edited test passes both before and after implementation.

## Tests removed

- None. No pre-existing test is inconsistent with the plan: the plan only adds the `--tmpfs /run/talkbox` options to the three persistent-container planners, the sentinel write in `image/entrypoint.sh`, and the readiness-wait calls in the `run_*` executors ("No aspect of `SPEC.md` / `SPEC.gen.md` is altered"), and no existing test asserts an exact full argument list, the absence of `--tmpfs`, or the exec command sequence, so every existing unit and e2e test continues to pass after implementation. Implementation note for the green phase: because `image/entrypoint.sh` changes only take effect in a rebuilt image, the `talkbox/base:latest` image must be rebuilt (e.g. `podman rmi talkbox/base:latest` before running `make test-e2e`) for the e2e suite to observe the new sentinel behaviour.
