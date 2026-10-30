# Dispute: the phase-28a e2e "short session starts the container" test is unpassable under the SPEC-mandated `sdrun` harness

Plan: [phase-28a-concurrent-session-stop-on-last-session](../plans/phase-28a-concurrent-session-stop-on-last-session.gen.md)

## Disputed test

- **Name:** `onbox concurrent sessions: the container stops only after the last session exits when the short session starts it`
- **File:** [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) (lines 176–202; failing assertion at line 194)
- **Related core files:** [lib/containers.sh](../../../lib/containers.sh) (`exec_in_container`, `stop_container_when_no_sessions_remain`)

## Exact failure output

```
not ok 30 onbox concurrent sessions: the container stops only after the last session exits when the short session starts it
# (in test file test/e2e/lifecycle.bats, line 194)
#   `sdrun podman inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null | grep -qx 'true'' failed
```

Reproduced deterministically (3/3 direct `bats` runs of the single test and in the full `make test-e2e` run: 82/83, only this test failing).

## Justification

`SPEC.md` (testing) mandates that every test invoking podman runs under `systemd-run` with `-p RuntimeMaxSec` and `-p KillMode=control-group` — which is exactly what the e2e helper `sdrun` (test/e2e/helpers.bash) does. The disputed test's assertions after `wait "$apid_first"` (line 194 "the container is still running", line 196 "exec sessions non-empty", lines 199–200 "the surviving session exits 0") require the container to **outlive the unit that started it**. The harness makes that impossible: the container's `conmon` and `pasta` processes are members of the starting session's transient unit cgroup (verified with `systemd-cgls --user-unit <unit>`), so when that unit deactivates, `KillMode=control-group` SIGKILLs them and the container — and every exec session inside it — dies, regardless of any talkbox behaviour. No podman option moves `conmon`/`pasta` out of the caller's cgroup (`--cgroups` modes per `.llm/ref/podman.docs/options/cgroups.md` either keep conmon with the caller or create sub-cgroups of the caller's cgroup), so no conforming implementation can pass lines 194–200.

Correlated reproduction (podman trace timestamps + `podman events`, talkbox-driven, harness-shaped):

```
1665.990  starter session: podman exec … bash -c sleep 8        (starts the container)
1666.358  surviving session: podman exec … echo ready > .session-ready && sleep 25
1674.086  starter's exec exits rc=0 (normal, after 8s)
1674.091  starter's tail: podman container inspect -f '{{json .ExecIDs}}'  → END 1674.137 rc=0
          (the listing sees the surviving session; the starter issues NO stop)
1674.193  surviving session's exec exits rc=137 — killed during the starter's
          unit deactivation (KillMode=control-group); podman events: exec_died → died (container) → exec_died
1674.204  surviving session's tail: listing → [] → stop -t 5 (no-op) → exits 137
1674.270  starter's unit exit observed by the test's wait → line 194 asserts Running=true → fails
```

The starting session's talkbox correctly **deferred** its stop (its only podman calls after the exec are the listing and nothing else; the sole `stop -t 5` in the trace belongs to the surviving session's tail after the harness already killed its exec). The failure is caused by the harness kill, not by the implementation. Without the systemd units — the same two-session talkbox scenario driven from plain shells — the behaviour matches the plan exactly: the starter exits, the container keeps running with the sibling session listed in `{{json .ExecIDs}}`, and the container stops when the last session exits.

The plan's stated e2e coverage "ordering variation with the short session first" ("the container keeps running after the second session exits and stops after the first (last) session exits") is therefore unachievable as written under the SPEC-mandated harness. A harness-compatible repair keeps the test's intent by verifying the starter's deferral through the e2e podman logging shim (`mk_podman_logging_shim`: assert the starter's invocation log contains no `stop -t 5 <ctr>` after its exec) and asserting that the last session's stop does stop the container, mirroring the already-passing companion test (`a short session exits without stopping a live longer session`, which starts the container with the long session and asserts only while the starter's unit is still alive).

## Evidence the implementation satisfies the plan

- Unit suite 314/314, including the five session-count tests in [test/unit/containers.bats](../../../test/unit/containers.bats) (stop when no sessions remain; defer when sessions remain; exit status propagation; listing failure falls back to stopping; interactive-session defer).
- E2e suite 82/83; the passing companion test `onbox concurrent sessions: a short session exits without stopping a live longer session` (test/e2e/lifecycle.bats line 153) covers the attacher-exits-first ordering end-to-end.
- Harness-free manual reproduction of the exact two-session scenario shows the plan behaviour (defer on non-last exit, stop on last exit).

## Related

- [Issue: concurrent session exit stops the container](../issues/concurrent-session-exit-stops-container.gen.md) — resolved by this implementation.
- [Review: multiple terminals attached to the same container](../reviews/multi-terminal-container-sessions.gen.md)
