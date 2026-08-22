# Test Harness Build

This document describes the test harness added to the repository, the important design decisions behind it, the issues encountered while building it, and the observed behaviour of each test command.

## Overview

The harness provides four `make` targets backed by `bats-core` (Bats 1.11.1):

- `make test-unit` - runs the unit tests under `test/unit/`
- `make test-e2e` - runs the end-to-end tests under `test/e2e/`
- `make test-canary` - runs the canary tests under `test/canary/` (intentionally failing, for harness development)
- `make test-timeout` - runs the timeout canary tests under `test/timeout/` (intentionally non-terminating, for harness development)

Each target is implemented by [test/run-suite.sh](test/run-suite.sh), which runs one bats suite, enforces the configurable timeouts, and writes a run record to `.llm/gen/runs/test-<suite>.gen.yaml`. Target definitions, timeout defaults and the `lint`/`format` targets live in [test/runner.mk](test/runner.mk). The top-level [Makefile](Makefile) simply includes it.

## Timeouts

Two shell variables tune the timeouts, with defaults applied by the makefile when they are not set:

- `GLOBAL_TEST_TIMEOUT` (default `600`) bounds the test suite as a whole.
- `INDIVIDUAL_TEST_TIMEOUT` (default `60`) bounds each individual test.

Both may be adjusted per invocation, e.g. `GLOBAL_TEST_TIMEOUT=1200 INDIVIDUAL_TEST_TIMEOUT=60 make test-unit`.

The individual timeout is enforced by exporting `BATS_TEST_TIMEOUT` into the bats environment (bats aborts a test which exceeds it and marks it failed). The global timeout is enforced by the command which launches the suite: each suite runs inside `systemd-run --user` with `RuntimeMaxSec` and `KillMode=control-group` passed via `-p`, which kills the whole process tree when the suite deadline is reached. This matches the specification that the unit and end-to-end suites be wrapped in `systemd-run` to prevent indefinite hangs.

## Run records

`make test-unit` and `make test-e2e` overwrite `.llm/gen/runs/test-unit.gen.yaml` and `.llm/gen/runs/test-e2e.gen.yaml`; the runner also writes records for the canary and timeout suites. The records are generated from the bats TAP output: [test/lib.bash](test/lib.bash) parses the `ok`/`not ok` lines (and the `# (in test file ...)` references) into totals and a list of failing tests of the form `test/<dir>/<file>.bats :: <test description>`, escapes single quotes for YAML (by doubling them), and writes the YAML. `started` is the UTC timestamp taken just before the suite runs; `exit` is the suite's exit status, or `timeout` when the suite-level timeout was reached. Writing the record does not alter the command's exit status: the status is captured first and the runner exits with it afterwards.

## Design decisions

- One runner script (`test/run-suite.sh`) serves all four targets, so timeout handling, TAP parsing and record writing are implemented once and exercised the same way everywhere.
- The suite runs under `systemd-run --user` when available, falling back to `timeout(1)` when it is not (e.g. no user systemd manager). A `timeout(1)` exit of `124` is treated as a suite-level timeout. The fallback is triggered only when the systemd-run unit failed to start (non-zero exit with no TAP output and no timeout marker), so genuine suite results are never double-run.
- Service output is captured via the `StandardOutput=file:` / `StandardError=file:` properties rather than a pty, so results are deterministic whether or not `make` runs from a terminal. This also cleanly separates bats output from `systemd-run`'s own bookkeeping, which is used to detect `Finished with result: timeout`.
- Records are written for the canary and timeout suites as well; the specification only requires records for the unit and end-to-end suites, but a uniform runner keeps the code simple and failed canary/timeout runs remain traceable.
- The canary and timeout suites contain only harness-focused tests: the canary tests assert something false, and the timeout canary runs `sleep 1000000` so it never terminates on its own.
- End-to-end smoke tests exercise the full pipeline by invoking the runner against temporary suites, verifying that passing suites yield `exit: 0` records and failing suites yield `exit: 1` records listing the failing test. Podman-based end-to-end tests (which will invoke `talkbox.sh` with `onbox`/`netbox`/`offbox`) are deferred until the core implementation exists; the harness infrastructure for them, including the suite-level `systemd-run` wrapping, is already in place.

## Issues encountered

- **Timeout variables invisible to tests**: the unit smoke tests could not see `GLOBAL_TEST_TIMEOUT`/`INDIVIDUAL_TEST_TIMEOUT` because `systemd-run` starts the service with a clean environment and only the explicitly passed `-E` variables are set. Fixed by passing all three timeout-related variables (`GLOBAL_TEST_TIMEOUT`, `INDIVIDUAL_TEST_TIMEOUT`, `BATS_TEST_TIMEOUT`) and `PATH` through `-E`.
- **Mixed stderr**: with `--pipe`, bats diagnostics and `systemd-run`'s own messages shared one stream, making output noisy. Resolved by using `StandardOutput=file:`/`StandardError=file:` so bats output is captured separately and `systemd-run` bookkeeping is consumed only for timeout detection.
- **Missing tooling**: the environment had neither `make`, `bats`, `shellcheck`, `shfmt` nor `expect`. All were installed via `apt` (`make`, `bats`, `shellcheck`, `shfmt`, `expect`).

## Test run results

Observed in this environment (Bats 1.11.1, GNU Make 4.4.1, systemd 257 with the user manager running):

- `make test-unit` - exit `0`; 5/5 tests passed; run record `exit: 0`.
- `make test-e2e` - exit `0`; 3/3 tests passed; run record `exit: 0`.
- `make test-canary` - exit nonzero (make `2`); 0/2 tests passed; run record `exit: 1`.
- `make test-timeout` with `GLOBAL_TEST_TIMEOUT=1200 INDIVIDUAL_TEST_TIMEOUT=2` - exit nonzero (make `2`); the non-terminating test was killed by the test-level timeout after about 2s; run record `exit: 1`.
- `make test-timeout` with `GLOBAL_TEST_TIMEOUT=3 INDIVIDUAL_TEST_TIMEOUT=1200` - exit nonzero (make `2`); the suite was killed by the suite-level timeout after about 3s; run record `exit: timeout`.

In all cases a failing test or a reached timeout yields a nonzero `make` exit, and `make test-unit`/`make test-e2e` exit `0` exactly when every test in the respective suite passed without reaching a timeout.
