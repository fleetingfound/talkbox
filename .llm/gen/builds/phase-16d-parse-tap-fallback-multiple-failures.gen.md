# Phase 16d: `parse_tap()` records every `not ok` failure when diagnostics are absent

Status: `SUCCESS`

This build implements [phase-16d-parse-tap-fallback-multiple-failures.gen.md](../plans/phase-16d-parse-tap-fallback-multiple-failures.gen.md), which resolves the issue [parse_tap() fallback drops all but the last failure when `not ok` lines lack diagnostics](../issues/parse-tap-fallback-drops-multiple-failures.gen.md) by buffering per-line pending descriptions in `parse_tap()` so the post-loop fallback emits one `(unknown) :: <desc>` entry per unrecorded failure, making `len(FAIL_NAMES) == FAIL` hold for every TAP stream.

## Overview

- `test/lib.bash` - in `parse_tap()`, the scalar `pending` is replaced by an array buffer: each `'not ok '*` line pushes its derived description (with the `(unnamed)` placeholder for empty descriptions) onto the buffer, the `# (in test file ...)` / `#  in test file ...` diagnostic branch pops the most recent buffered description and appends `<src> :: <desc>` to `FAIL_NAMES` (leaving earlier buffered entries untouched), and the post-loop fallback appends one `(unknown) :: <desc>` entry per remaining buffered description. No other functions or call sites were modified.
- `test/unit/parse-tap.bats` - four new unit tests in the existing `feed_tap` style cover the consecutive-`not ok` regression, diagnostic-on-latest, diagnostic-on-first, and mixed `ok`/`# skip`/`not ok` consistency cases.

## Test edits

No existing tests were edited. Four tests were added to `test/unit/parse-tap.bats` solely to implement the tests required by the plan:

- Plan (L71-72): "Two consecutive `not ok` lines with no diagnostic lines produce two `(unknown) :: <name>` entries and `len(FAIL_NAMES) == FAIL` (the core regression)."
- Plan (L73-75): "Two consecutive `not ok` lines where the second carries a `# (in test file ...)` diagnostic: the first is recorded as `(unknown) :: <name1>` and the second as `<src> :: <name2>`, with `len(FAIL_NAMES) == FAIL`."
- Plan (L76-78): "Two consecutive `not ok` lines where the first carries a diagnostic and the second does not: the first is `<src> :: <name1>` and the second is `(unknown) :: <name2>`."
- Plan (L79-81): "A mix of multiple `not ok` lines, some with and some without diagnostics, interspersed with `ok` and `ok ... # skip` lines, leaves `FAIL`, `PASS`, `SKIP` and `FAIL_NAMES` mutually consistent."

The plan's note "No end-to-end tests are required; the bug is fully exercised at the unit level" (L88) is honoured; no e2e tests were added or edited.

## Verification

- `make test-unit` - exit `0`; 277/277 tests passed, including the four new `parse-tap.bats` tests and the unchanged Phase 16c cases.
- `make test-e2e` - exit `0`; 76/76 tests passed.
- ShellCheck (`make lint`) and `shfmt` (`make format`) are clean on the modified files.
