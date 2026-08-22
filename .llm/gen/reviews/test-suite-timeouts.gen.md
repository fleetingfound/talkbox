# Review: Test suite timeout implementation

Related spec: [SPEC.md §testing](../../../SPEC.md)
Related harness: [test/runner.mk](../../../test/runner.mk), [test/run-suite.sh](../../../test/run-suite.sh), [test/e2e/helpers.bash](../../../test/e2e/helpers.bash)

## Spec requirements

[SPEC.md §testing](../../../SPEC.md) imposes two timeout requirements:

1. **Per-test (podman-invoking):** "Any test which invokes `podman`, including those which call `talkbox.sh`, `onbox`, `netbox` or `offbox`, must be called via `systemd-run` with the options `RuntimeMaxSec` and `KillMode=control-group` passed via the flag `-p` in order to prevent commands from hanging indefinitely."
2. **Suite-level:** "Additionally, the `make` implementation wraps the entirety of both the unit test suite and end-to-end test suite in `systemd-run` to prevent indefinite hangs at the suite level."

## Implementation

### Suite-level timeout (requirement 2) — correctly implemented

[test/run-suite.sh](../../../test/run-suite.sh) function `run_with_systemd()` wraps the entire bats invocation:

```bash
systemd-run --user --wait --collect \
    -p "RuntimeMaxSec=$GLOBAL_TEST_TIMEOUT" \
    -p KillMode=control-group \
    ...
    -- bash -c 'exec bats --tap "$@"' -- "${files[@]}"
```

A `timeout(1)` fallback (`run_with_timeout`) is used when `systemd-run` is unavailable or fails to produce output. Both paths set `BATS_TEST_TIMEOUT=$INDIVIDUAL_TEST_TIMEOUT` for the inner bats process. Defaults (`GLOBAL_TEST_TIMEOUT=600`, `INDIVIDUAL_TEST_TIMEOUT=60`) are defined in [test/runner.mk](../../../test/runner.mk) and exported.

**Verified:** running with `GLOBAL_TEST_TIMEOUT=5` against a suite containing `sleep 1000000` killed the suite at 5s and wrote `exit: timeout` to the run record.

### Per-test timeout for non-podman tests — correctly implemented

The individual-test timeout for non-podman tests (all unit tests) is implemented via bats-core's documented `BATS_TEST_TIMEOUT` environment variable (bats 1.11.1; see `.llm/ref/bats-core.docs/bats.7.ronn` line 375: "the number of seconds after which a test (including setup) will be aborted and marked as failed"). The runner sets `BATS_TEST_TIMEOUT=$INDIVIDUAL_TEST_TIMEOUT` in both the `systemd-run` and `timeout(1)` code paths.

**Verified:** `make test-timeout` killed `sleep 1000000` after 60s and reported `not ok 1 ... # timeout after 60s`.

### Per-test timeout for podman-invoking tests (requirement 1) — correctly implemented

[test/e2e/helpers.bash](../../../test/e2e/helpers.bash) defines `sdrun`:

```bash
sdrun() {
    systemd-run --user --wait --collect --pipe \
        -p "RuntimeMaxSec=$SD_TIMEOUT" \
        -p KillMode=control-group \
        -E "PATH=$PATH" \
        -- "$@"
}
```

All podman-invoking e2e tests route through `sdrun` (directly or via `run_onbox_noninteractive`, which calls `sdrun` internally). No e2e test invokes `podman`, `talkbox.sh`, or `onbox` outside of `sdrun`. Unit tests source libraries and call functions directly without invoking podman, so they correctly do not use `sdrun`.

## Assessment

Both spec requirements are satisfied. Both timeouts were empirically verified to fire. The implementation is sound.

## Minor refinements (not defects)

### 1. `sdrun` timeout is not derived from `INDIVIDUAL_TEST_TIMEOUT`

`SD_TIMEOUT` defaults to `60` hardcoded in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash), rather than being derived from `INDIVIDUAL_TEST_TIMEOUT`. If a user overrides `INDIVIDUAL_TEST_TIMEOUT=30 make test-e2e`, the bats-level per-test timeout would be 30s but each `sdrun`-wrapped podman call would still allow 60s. This is harmless (the bats timeout would fire first and `--collect` cleans up the orphaned unit), but deriving `SD_TIMEOUT` from `INDIVIDUAL_TEST_TIMEOUT` would make the two layers consistent.

### 2. `sdrun` and `BATS_TEST_TIMEOUT` fire simultaneously at default 60s

With both at 60s, a hanging podman call would trigger `sdrun`'s `RuntimeMaxSec` and `BATS_TEST_TIMEOUT` at roughly the same instant. If `sdrun`'s timeout fired slightly before bats's, the test would fail with a clear podman-killed error rather than a bats timeout. Setting `SD_TIMEOUT` to a few seconds less than `INDIVIDUAL_TEST_TIMEOUT` (or `INDIVIDUAL_TEST_TIMEOUT - 5`) would ensure the inner timeout fires first, producing a cleaner diagnostic.

### 3. Interactive test's `expect` timeout exceeds `sdrun`'s timeout

Already filed as [issue: interactive e2e test has inconsistent timeouts](../issues/interactive-test-timeout-mismatch.gen.md). The `expect` script sets `set timeout 90` while `sdrun` uses `RuntimeMaxSec=60`.

### 4. `BATS_TEST_TIMEOUT` is set only inside the runner

`runner.mk` exports `GLOBAL_TEST_TIMEOUT` and `INDIVIDUAL_TEST_TIMEOUT` but not `BATS_TEST_TIMEOUT`. The runner derives it internally, so `make test-unit` / `make test-e2e` are correct. Running `bats test/unit/` directly would have no per-test timeout. This is acceptable since the spec mandates invocation via `make`, but a note in the runner's help text could document this.
