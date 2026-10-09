# Phase 23c test record: e2e nested `sdrun` units die with the parent suite unit

Implements [Phase 23c](../plans/phase-23c-e2e-nested-units-die-with-parent.gen.md) — which resolves the [interrupted e2e suite run races the immediately following run](../issues/interrupted-e2e-suite-run-races-next-run.gen.md) issue — by giving the suite wrapper in `test/run-suite.sh` a deterministic, run-unique transient unit name exported to the suite as `TALKBOX_SUITE_UNIT` and having each `sdrun` unit in `test/e2e/helpers.bash` declare a `StopPropagatedFrom=` dependency on it, so stopping the wrapper (or its `RuntimeMaxSec` expiry) stops the suite's in-flight nested `sdrun` units together with their podman processes, while the `timeout(1)` fallback and direct `bats` runs keep creating plain transient units exactly as before (`SPEC.md` *testing*: the `systemd-run` wrapping with `RuntimeMaxSec` and `KillMode=control-group` which prevents commands from hanging indefinitely). This record describes the tests for that behaviour; both suites are green post-implementation.

## New tests

Three harness tests in the new `test/e2e/suite-unit.bats`:

- *sdrun declares StopPropagatedFrom on the exported suite unit* — runs the real `sdrun` (via `load helpers`) with `TALKBOX_SUITE_UNIT` set to a probe unit name; the nested unit reads its own unit name from its cgroup and `systemctl --user show -p StopPropagatedFrom` executed from inside the unit must report the exported name (plan: "when set, adds a stop-propagation dependency on it to its own `systemd-run` invocation (via `--property StopPropagatedFrom=`)"); the dependency is declared against a probe unit that never exists, pinning that declaring it is safe even when the parent has gone away.
- *sdrun omits StopPropagatedFrom without an exported suite unit* — unsets `TALKBOX_SUITE_UNIT` (the `timeout(1)` fallback / direct-`bats` path) and asserts the same in-unit probe reports an empty dependency (plan: "When the name is unset, `sdrun` behaves exactly as today"; observable via the created unit's properties).
- *a nested sdrun unit is stopped when the suite wrapper unit is stopped* — under `make test-e2e` (skipped for direct `bats` runs, which have no exported wrapper), launches a real nested suite through `test/run-suite.sh` with bounded harness timeouts (`GLOBAL_TEST_TIMEOUT=120`, `INDIVIDUAL_TEST_TIMEOUT=45`); the nested suite records its wrapper name and starts a nested `sdrun sleep 20` unit; the test asserts the recorded wrapper has the `talkbox-*.service` form, that the nested unit is active and carries `StopPropagatedFrom=<wrapper>`, then stops the wrapper and polls (bounded) that the nested unit is inactive and that the nested runner still wrote its run record. Every wait is a poll loop (≤ 20 s each) backstopped by the wrapper's `RuntimeMaxSec`, so the test cannot hang (plan: "bounded by the harness timeouts so the test itself cannot hang").

## Tests edited

None. The plan supersedes no existing test: the harness smoke tests (`make exposes the four test targets` and the two run-record tests) and every product test keep passing unchanged against the modified harness.

## Tests removed

None.

## Harness changes under test

- `test/run-suite.sh` — `run_with_systemd` now passes `--unit=talkbox-<target>-<epoch>-<pid>.service` together with `-E TALKBOX_SUITE_UNIT=<same name>`; the `timeout(1)` fallback runs `bats` under `env -u TALKBOX_SUITE_UNIT`, so the fallback creates plain transient units exactly as today; and when the runner is invoked from a bats process (nested suite runs), the unit's `PATH` drops the libexec dir bats prepends, because `systemd-run` does not carry the exported `bats_readlinkf` function into units — without this the nested `systemd-run` path failed instantly and silently degraded to the fallback (no wrapper unit, no export), which also blocked the new stop-propagation test from running nested suites for real.
- `test/e2e/helpers.bash` — `sdrun` prepends `-p StopPropagatedFrom=$TALKBOX_SUITE_UNIT` only when the variable is set.

## Suite results

Post-implementation: `make test-unit` reports total=317 pass=317 fail=0 skip=0 exit=0 and `make test-e2e` reports total=78 pass=78 fail=0 skip=0 exit=0, with the new stop-propagation test running for real under `make test-e2e`. `make test-canary` and `GLOBAL_TEST_TIMEOUT=15 INDIVIDUAL_TEST_TIMEOUT=8 make test-timeout` still fail as designed, confirming the failure and timeout detection paths under the `--unit` wrapper. A live check of the phase behaviour — a `make test-e2e` run stopped through its wrapper unit — showed its in-flight nested podman unit (carrying `StopPropagatedFrom=<wrapper>`) deactivating with the wrapper and no leftover `talkbox` units.
