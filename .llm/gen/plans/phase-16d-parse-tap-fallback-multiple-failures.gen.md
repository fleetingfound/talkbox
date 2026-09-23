# Phase 16d: `parse_tap()` records every `not ok` failure when diagnostics are absent

#flow/unified #model/default

## Aspects of the specification to implement

This phase resolves the issue
[parse_tap() fallback drops all but the last failure when `not ok` lines lack diagnostics](../issues/parse-tap-fallback-drops-multiple-failures.gen.md).
It is a test-harness correctness fix and does not implement or defer any aspect
of `SPEC.md` / `SPEC.gen.md`.

## External-facing functionality

After this phase, the YAML run records written by `test/run-suite.sh` (via
`write_record`) will record one `fail:` entry per `not ok` line even when the
TAP stream contains two or more consecutive `not ok` lines without intervening
`# (in test file ...)` / `#  in test file ...` diagnostics. For every TAP
stream, `len(FAIL_NAMES) == FAIL` holds, so the run record's `fail:` list
agrees with the `totals.fail` counter.

Failures that do carry a diagnostic continue to be recorded as
`<src> :: <name>`; failures without a diagnostic continue to be recorded as
`(unknown) :: <name>`. The empty-description placeholder `(unnamed)` introduced
in Phase 16c is preserved.

## Files to be created

None. Existing files are modified.

## Files to be read during implementation

- [test/lib.bash](test/lib.bash) — the function under test (`parse_tap`).
- [test/unit/parse-tap.bats](test/unit/parse-tap.bats) — the existing unit
  coverage added by Phase 16c, whose style and `feed_tap` helper the new cases
  mirror.
- [test/run-suite.sh](test/run-suite.sh) — the caller, to confirm the
  `FAIL` / `FAIL_NAMES` agreement contract the fix must preserve.

## Key internal interfaces to be modified

- `parse_tap()` in `test/lib.bash`:
  - Replace the single scalar `pending` with a buffered array of descriptions
    awaiting diagnostic resolution. Each `'not ok '*` line pushes its derived
    description (with the `(unnamed)` placeholder for empty descriptions) onto
    the buffer.
  - The `# (in test file ...)` / `#  in test file ...` diagnostic branch pops
    the most recent buffered description (if any) and appends
    `<src> :: <desc>` to `FAIL_NAMES`, leaving earlier buffered entries
    untouched so they are still resolved by the post-loop fallback.
  - The post-loop fallback iterates over any descriptions remaining in the
    buffer and appends one `(unknown) :: <desc>` entry per remaining
    description, so every `not ok` line is represented exactly once.

  No other functions or call sites are modified; `write_record`, the run-record
  format and the rest of `test/run-suite.sh` are unchanged.

## Design note

The issue suggests two fix directions: (a) append immediately to `FAIL_NAMES`
in the `'not ok '*` branch and have the diagnostic branch rewrite the last
entry with the `<src> ::` prefix, or (b) buffer per-line pending entries so the
post-loop fallback emits one entry per unrecorded failure. This plan adopts
(b), which preserves the existing three-branch structure of `parse_tap()` and
keeps the diagnostic branch's "append-and-clear" semantics, minimising the
diff and the risk of regressing the Phase 16c behaviour.

## Tests

This phase requires tests to be implemented (in `test/unit/parse-tap.bats`):

- Unit tests:
  - Two consecutive `not ok` lines with no diagnostic lines produce two
    `(unknown) :: <name>` entries and `len(FAIL_NAMES) == FAIL` (the core
    regression).
  - Two consecutive `not ok` lines where the second carries a `# (in test
    file ...)` diagnostic: the first is recorded as `(unknown) :: <name1>` and
    the second as `<src> :: <name2>`, with `len(FAIL_NAMES) == FAIL`.
  - Two consecutive `not ok` lines where the first carries a diagnostic and
    the second does not: the first is `<src> :: <name1>` and the second is
    `(unknown) :: <name2>`.
  - A mix of multiple `not ok` lines, some with and some without diagnostics,
    interspersed with `ok` and `ok ... # skip` lines, leaves `FAIL`,
    `PASS`, `SKIP` and `FAIL_NAMES` mutually consistent.
  - Existing Phase 16c cases (single failure with/without diagnostic,
    empty-description, directive, and the passing/skipped pin) continue to
    pass unchanged.

No end-to-end tests are required; the bug is fully exercised at the unit level
by feeding TAP fragments directly to `parse_tap()`.
