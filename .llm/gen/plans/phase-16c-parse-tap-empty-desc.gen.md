# Phase 16c: `parse_tap()` records failing tests with empty descriptions

#flow/unified #model/default

## Aspects of the specification to implement

This phase resolves the issue
[parse_tap() drops failing tests with empty descriptions from FAIL_NAMES](../issues/parse-tap-empty-desc-drops-fail-name.gen.md).
It is a test-harness correctness fix rather than an aspect of `SPEC.md` /
`SPEC.gen.md`; no specification section is being implemented or deferred.

## External-facing functionality

After this phase, the YAML run records written by `test/run-suite.sh` (via
`write_record`) will no longer silently omit failing tests whose TAP
description is empty. For every `not ok` line, `len(FAIL_NAMES)` will equal
`FAIL`. Empty-description failures are recorded with a placeholder name so the
run record's `fail:` list stays consistent with the `totals.fail` counter.

## Files to be created

- `test/unit/parse-tap.bats` — a new unit test file exercising `parse_tap()`
  by sourcing `test/lib.bash` and feeding it crafted TAP fragments. This is
  the first dedicated unit coverage for `parse_tap()`.

## Files to be read during implementation

- [test/lib.bash](test/lib.bash) — the function under test (`parse_tap` and
  `write_record`).
- [test/run-suite.sh](test/run-suite.sh) — the caller, to confirm the
  contract the fix must preserve (`FAIL` / `FAIL_NAMES` agreement).
- [test/unit/helpers.bash](test/unit/helpers.bash) — the unit-test helper
  conventions (`PROJECT_ROOT` derivation; sourcing pattern).
- [test/unit/smoke.bats](test/unit/smoke.bats) — the existing unit-test style
  to mirror.

## Key internal interfaces to be modified

- `parse_tap()` in `test/lib.bash`:
  - In the `'not ok '*` branch, after the description is derived into `desc`,
    substitute a placeholder (e.g. `(unnamed)`) when `desc` is empty before
    assigning it to `pending`. This single change makes both
    `[[ -n "$pending" ]]` guard sites (the `# (in test file` diagnostic
    branch and the post-loop fallback) record an entry, so
    `len(FAIL_NAMES) == FAIL` holds for empty-description failures.
  - The diagnostic-branch entry continues to take the form
    `<src> :: <pending>` and the post-loop fallback continues to take the
    form `(unknown) :: <pending>`; only the value of `pending` changes when
    the description is empty.

No other functions or call sites are modified; `write_record`, the run-record
format and the rest of `test/run-suite.sh` are unchanged.

## Tests

This phase requires tests to be implemented:

- Unit tests (in `test/unit/parse-tap.bats`):
  - A failing test with a non-empty description and a `# (in test file ...)`
    diagnostic is recorded under `FAIL_NAMES` with the `src :: name` form
    (pins existing behaviour).
  - A failing test with an empty description and a `# (in test file ...)`
    diagnostic is recorded (currently dropped) and `len(FAIL_NAMES) == FAIL`.
  - A failing test with an empty description that carries a directive
    (`not ok 1  # timeout after 1s`) is recorded and
    `len(FAIL_NAMES) == FAIL`.
  - A failing test whose TAP output has no `# (in test file ...)` diagnostic
    line falls back to the `(unknown) :: <pending>` entry, including for an
    empty description (placeholder substituted).
  - A passing `ok` line and a skipped `ok ... # skip` line leave `FAIL` and
    `FAIL_NAMES` untouched (pins existing behaviour).

No end-to-end tests are required; the bug is fully exercised at the unit
level by feeding TAP fragments directly to `parse_tap()`.
