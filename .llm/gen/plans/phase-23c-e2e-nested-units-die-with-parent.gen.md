# Phase 23c: E2e nested `sdrun` units die with the parent suite unit

#flow/pinner #model/default

Resolves the issue [interrupted e2e suite run races the immediately following run](../../issues/interrupted-e2e-suite-run-races-next-run.gen.md).

## specification

This phase hardens the test harness required by the [testing](../../../SPEC.md#testing) section of [SPEC.md](../../../SPEC.md) (the `systemd-run` wrapping which prevents commands from hanging indefinitely); it introduces no product behaviour. All product aspects of the specification remain implemented and deferred here.

## external-facing functionality

- Killing an interrupted `make test-e2e` (or `make test-unit`) suite run now also stops the suite's in-flight nested `sdrun` units, together with their `podman build`/`start`/`rm` processes, so the immediately following suite run is not raced by leftover units mutating podman storage, and its run record can be trusted.
- Behaviour is unchanged when the suite runs outside the `systemd-run` wrapper (the `timeout(1)` fallback or a direct `bats` invocation): `sdrun` creates plain transient units exactly as today.

## files to create

None. Existing files are modified:

- [test/run-suite.sh](../../../test/run-suite.sh) — deterministic suite-unit name and its export.
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — the `sdrun` stop-propagation dependency.
- test files listed under *tests* below.

## files to read during implementation

- [SPEC.md](../../../SPEC.md) (testing)
- [test/run-suite.sh](../../../test/run-suite.sh) (`run_with_systemd`, `run_with_timeout`)
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) (`sdrun`, `INDIVIDUAL_TEST_TIMEOUT`/`SD_TIMEOUT`)
- [test/e2e/smoke.bats](../../../test/e2e/smoke.bats) (the harness-level tests)
- [test/runner.mk](../../../test/runner.mk)
- the choice [leftover e2e `sdrun` units from an interrupted suite run](../choices/e2e-leftover-unit-drain.gen.md)

## key internal interfaces

- `run_with_systemd` in `test/run-suite.sh` starts the suite under a deterministic, run-unique transient unit name (via `systemd-run --unit`), and exports that name to the suite's environment so it reaches `bats` and the per-invocation helpers.
- `sdrun` in `test/e2e/helpers.bash` reads the exported suite-unit name from the environment and, when set, adds a stop-propagation dependency on it to its own `systemd-run` invocation (via `--property StopPropagatedFrom=`), keeping its existing `KillMode=control-group` so stopping the nested unit kills its podman processes. When the name is unset, `sdrun` behaves exactly as today. The dependency must be safe to declare even when the parent unit has already gone away.
- Both the e2e and unit suite wrappers flow through `test/run-suite.sh`, so the mechanism covers `make test-unit` and `make test-e2e` uniformly.

## tests

Requires tests, per the [testing](../../../SPEC.md#testing) section of the specification, via `make test-unit` and `make test-e2e`:

- end-to-end harness tests (`test/e2e/smoke.bats` or a focused harness test): a nested unit started from within a suite run is stopped when the suite wrapper unit is stopped, bounded by the harness timeouts so the test itself cannot hang; and the fallback path — no exported suite-unit name — creates `sdrun` units without the dependency (observable via the created unit's properties or the `sdrun` invocation).
- unit-level coverage is limited to what can be inspected without a session `systemd-run` (the smoke-level assertions above suffice); no product unit tests apply since no product file changes.

No existing tests are superseded; the existing harness smoke tests continue to pass unchanged.
