# Phase 16c: `parse_tap()` records failing tests with empty descriptions

Status: `SUCCESS`

This build implements [phase-16c-parse-tap-empty-desc.gen.md](../plans/phase-16c-parse-tap-empty-desc.gen.md), which resolves the issue [parse_tap() drops failing tests with empty descriptions from FAIL_NAMES](../issues/parse-tap-empty-desc-drops-fail-name.gen.md) by substituting an `(unnamed)` placeholder for empty TAP descriptions in `parse_tap()`, so the run records written by `test/run-suite.sh` no longer silently omit failing tests whose description is empty and `len(FAIL_NAMES) == FAIL` holds for every `not ok` line.

## Overview

- `test/lib.bash` - in `parse_tap()`'s `'not ok '*` branch, after the description is derived into `desc`, an empty `desc` is replaced with the placeholder `(unnamed)` before being assigned to `pending`. This single change makes both `[[ -n "$pending" ]]` append sites record an entry: the `# (in test file ...)` diagnostic branch (`<src> :: <pending>`) and the post-loop `(unknown) :: <pending>` fallback. No other functions or call sites were modified.
- `test/unit/parse-tap.bats` - new unit test file exercising `parse_tap()` by sourcing `test/lib.bash` and feeding it crafted TAP fragments; the first dedicated unit coverage for the function.

During implementation a further pre-existing limitation was discovered and left unaddressed, as it is outside this plan's scope: the post-loop `(unknown) :: <pending>` fallback records only the last of consecutive `not ok` lines lacking diagnostic lines, tracked as issue [parse_tap() fallback drops all but the last failure when `not ok` lines lack diagnostics](../issues/parse-tap-fallback-drops-multiple-failures.gen.md).

## Test edits

No existing tests were edited. The new test file `test/unit/parse-tap.bats` was created solely to implement the tests required by the plan:

- Plan (L58-63): "A failing test with a non-empty description and a `# (in test file ...)` diagnostic is recorded under `FAIL_NAMES` with the `src :: name` form (pins existing behaviour)."
- Plan (L64-65): "A failing test with an empty description and a `# (in test file ...)` diagnostic is recorded (currently dropped) and `len(FAIL_NAMES) == FAIL`."
- Plan (L66-67): "A failing test with an empty description that carries a directive (`not ok 1  # timeout after 1s`) is recorded and `len(FAIL_NAMES) == FAIL`."
- Plan (L68-70): "A failing test whose TAP output has no `# (in test file ...)` diagnostic line falls back to the `(unknown) :: <pending>` entry, including for an empty description (placeholder substituted)."
- Plan (L71-72): "A passing `ok` line and a skipped `ok ... # skip` line leave `FAIL` and `FAIL_NAMES` untouched (pins existing behaviour)."

The plan's note "No end-to-end tests are required; the bug is fully exercised at the unit level" (L73) is honoured; no e2e tests were added or edited.

## Verification

- `make test-unit` - exit `0`; 273/273 tests passed, including the six new `parse-tap.bats` tests.
- `make test-e2e` - exit `0` on two consecutive full runs (76/76 tests passed each). One earlier full run reported a single unreproduced failure; the change only alters TAP parsing for empty descriptions, which no e2e test exercises, so that failure is environmental flakiness rather than a regression (it passed on both subsequent runs).
- ShellCheck (`make lint`) and `shfmt` (`make format`) are clean on the modified files.
