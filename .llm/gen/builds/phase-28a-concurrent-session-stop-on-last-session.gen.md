# Phase 28a: stop the container only when no exec sessions remain

Status: `BLOCKED`

Implements [the plan](../plans/phase-28a-concurrent-session-stop-on-last-session.gen.md), which resolves [the concurrent-session-exit issue](../issues/concurrent-session-exit-stops-container.gen.md) (marked complete): `exec_in_container` in [lib/containers.sh](../../../lib/containers.sh) now ends its exec tail by calling the new `stop_container_when_no_sessions_remain`, which lists the container's live exec sessions with `podman container inspect -f '{{json .ExecIDs}}'` (a quoted element in the listing is a session) and calls `stop_container` only when the listing shows none or fails to materialise, so the last of several concurrent sessions to exit stops the container whichever one started it, any live session (another terminal's exec, a concurrent `setup.sh` or `sync` exec) defers the stop, and a failed or unsupported listing falls back to the legacy unconditional stop for podman versions without exec-session visibility. The plan's named listing command `podman exec list` was verified against the installed podman 5.4.2 and the podman reference docs and does not exist as a subcommand; the implemented enumeration uses the supported `.ExecIDs` container-inspect field (the mechanism the plan's own e2e helper `container_exec_sessions` and the unit shim's `ExecIDs`/`exec list` staging both anticipate), and the fully-qualified `podman container inspect` form keeps the phase-20e dispatcher pin "no `podman inspect -f` on the offbox path" intact.

## Changes

- [lib/containers.sh](../../../lib/containers.sh): new `stop_container_when_no_sessions_remain` (listing + conditional stop, placed next to `stop_container`); `exec_in_container`'s trailing unconditional `stop_container "$ctr"` replaced by the conditional call; every other stop site (`stop_and_die`, `rollback_creation_and_die`, `run_recreate`'s final stop) unchanged per the failure-stop-semantics choice.
- [MAP.gen.md](../../../MAP.gen.md): the `lib/containers.sh` entry now describes the stop-on-last-session behaviour.
- No changes to `test/` (the red-phase tests for this phase were pre-committed in c3be776) and no changes to the other exec/stop paths.

## Verification

- `make lint` passes; shellcheck and `shfmt -d` clean on `lib/containers.sh`.
- `make test-unit`: 314/314, including the five red session-count tests.
- `make test-e2e`: 82/83 — the single failure is the disputed test (below); the companion concurrent-session test (`a short session exits without stopping a live longer session`) passes.
- Harness-free manual reproduction of the two-session scenario shows the exact plan behaviour: starter exits, container keeps running with the sibling session listed, container stops when the last session exits.

## Disputed test

[E2e `onbox concurrent sessions: the container stops only after the last session exits when the short session starts it`](../disputes/phase-28a-e2e-starter-exit-harness-kill.gen.md) — the test requires the container to outlive its starting session's transient unit, which the SPEC-mandated `sdrun` harness (`systemd-run -p KillMode=control-group`) kills deterministically (conmon and pasta are members of the starting unit's cgroup), so the assertions after the starter's exit are unpassable for any implementation; correlated trace/event evidence and a suggested harness-compatible repair are in the dispute document.

## Linked documents

- Plan: [phase-28a-concurrent-session-stop-on-last-session.gen.md](../plans/phase-28a-concurrent-session-stop-on-last-session.gen.md)
- Dispute: [phase-28a-e2e-starter-exit-harness-kill.gen.md](../disputes/phase-28a-e2e-starter-exit-harness-kill.gen.md)
- Issue resolved: [concurrent-session-exit-stops-container.gen.md](../issues/concurrent-session-exit-stops-container.gen.md) — marked complete; the unconditional post-exec stop no longer exists.
