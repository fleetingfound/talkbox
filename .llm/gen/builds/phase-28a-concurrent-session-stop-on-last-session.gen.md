# Phase 28a: stop the container only when no exec sessions remain

Status: `SUCCESS`

Implements [the plan](../plans/phase-28a-concurrent-session-stop-on-last-session.gen.md), which resolves [the concurrent-session-exit issue](../issues/concurrent-session-exit-stops-container.gen.md) (marked complete): `exec_in_container` in [lib/containers.sh](../../../lib/containers.sh) now ends its exec tail by calling the new `stop_container_when_no_sessions_remain`, which lists the container's live exec sessions with `podman container inspect -f '{{json .ExecIDs}}'` (a quoted element in the listing is a session) and calls `stop_container` only when the listing shows none or fails to materialise, so the last of several concurrent sessions to exit stops the container whichever one started it, any live session (another terminal's exec, a concurrent `setup.sh` or `sync` exec) defers the stop, and a failed or unsupported listing falls back to the legacy unconditional stop for podman versions without exec-session visibility. The plan's named listing command `podman exec list` was verified against the installed podman 5.4.2 and the podman reference docs and does not exist as a subcommand; the implemented enumeration uses the supported `.ExecIDs` container-inspect field (the mechanism the plan's own e2e helper `container_exec_sessions` and the unit shim's `ExecIDs`/`exec list` staging both anticipate), and the fully-qualified `podman container inspect` form keeps the phase-20e dispatcher pin "no `podman inspect -f` on the offbox path" intact.

## Changes

- [lib/containers.sh](../../../lib/containers.sh): new `stop_container_when_no_sessions_remain` (listing + conditional stop, placed next to `stop_container`); `exec_in_container`'s trailing unconditional `stop_container "$ctr"` replaced by the conditional call; every other stop site (`stop_and_die`, `rollback_creation_and_die`, `run_recreate`'s final stop) unchanged per the failure-stop-semantics choice.
- [MAP.gen.md](../../../MAP.gen.md): the `lib/containers.sh` entry now describes the stop-on-last-session behaviour.
- No changes to `test/` (the red-phase tests for this phase were pre-committed in c3be776) and no changes to the other exec/stop paths.

## Disputed test, resolved by the verdict

The e2e `onbox concurrent sessions: the container stops only after the last session exits when the short session starts it` test initially failed for any implementation: its assertions after the starter session's exit require the container to outlive the starter's transient unit, which the SPEC-mandated `sdrun` harness (`systemd-run -p KillMode=control-group`) sweeps away (conmon and pasta live in the starting unit's cgroup). [The dispute document](../disputes/phase-28a-e2e-starter-exit-harness-kill.gen.md) was resolved by [the verdict document](../verdicts/phase-28a-e2e-starter-exit-harness-kill.gen.md), which found the test `BROKEN_TEST` (harness artefact, not an implementation defect — independently validated by a harness-free reproduction showing the exact plan behaviour) and prescribed a repair holding the starter's unit open past the talkbox session via a new `run_onbox_session_holding_unit` helper in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash); the repair is applied in [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) with every original behavioural assertion retained, and the test now passes, including a red-check against a non-deferring regression. The dispute and verdict are marked complete in their indexes.

## Verification

- `make lint` and `make format` pass; shellcheck and `shfmt -d` clean.
- `make test-unit`: 314/314, including the five session-count decision tests (listing consulted after the exec; sessions remaining → no stop; exec exit status propagates; failed/unsupported listing → stop; interactive-session variant).
- `make test-e2e`: 83/83 after the verdict-mandated repair, including both concurrent-session ordering tests.

## Linked documents

- Plan: [phase-28a-concurrent-session-stop-on-last-session.gen.md](../plans/phase-28a-concurrent-session-stop-on-last-session.gen.md) — marked complete in the plans index.
- Dispute: [phase-28a-e2e-starter-exit-harness-kill.gen.md](../disputes/phase-28a-e2e-starter-exit-harness-kill.gen.md) and verdict: [phase-28a-e2e-starter-exit-harness-kill.gen.md](../verdicts/phase-28a-e2e-starter-exit-harness-kill.gen.md) — one sentence: the disputed starter-exit e2e test was unpassable for any implementation because the SPEC-mandated harness's unit deactivation kills the started container, resolved by holding the unit open past the session with all original assertions retained.
- Issue resolved: [concurrent-session-exit-stops-container.gen.md](../issues/concurrent-session-exit-stops-container.gen.md) — marked complete; the unconditional post-exec stop no longer exists.
