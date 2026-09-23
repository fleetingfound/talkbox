# `parse_tap()` fallback drops all but the last failure when `not ok` lines lack diagnostics

## Summary

In `parse_tap()`, the post-loop fallback that emits `(unknown) :: <pending>`
records only the single most recent `pending` value. When a TAP stream
contains two or more consecutive `not ok` lines without an intervening
`# (in test file ...)` / `#  in test file ...` diagnostic line, every failure
before the last is silently dropped, so `len(FAIL_NAMES) < FAIL` and the run
record's `fail:` list disagrees with the `totals.fail` counter.

## Affected files

- [test/lib.bash](test/lib.bash) — `parse_tap()` (the post-loop fallback at the
  end of the `while` loop).

## Root cause

`pending` is overwritten by each `'not ok '*` line and is only appended to
`FAIL_NAMES` (as `(unknown) :: <pending>`) once, after the loop:

```bash
if [[ -n "$pending" ]]; then
	FAIL_NAMES+=("(unknown) :: $pending")
fi
```

The `# (in test file ...)` diagnostic branch is what normally appends and
clears `pending` per failure, but a TAP stream without such diagnostic lines
relies entirely on the fallback, which keeps only the last `not ok`.

For example, feeding:

```
1..2
not ok 1 first failure
not ok 2 second failure
```

produces `FAIL=2` with `FAIL_NAMES` of length 1 (only
`(unknown) :: second failure`). The empty-description case (e.g. two
`not ok 1 ` lines) is likewise affected.

## Consequences

- For TAP streams without diagnostic lines (the case the `(unknown)` fallback
  exists to handle), multiple failures are under-reported in the run record's
  `fail:` list.
- The `FAIL` counter and `fail:` list disagree, the same defect class fixed for
  empty descriptions in [Phase 16c](../plans/phase-16c-parse-tap-empty-desc.gen.md).

## Suggested fix direction

Track whether any `not ok` line is awaiting a diagnostic or fallback entry
(e.g. append immediately to `FAIL_NAMES` in the `'not ok '*` branch and have
the diagnostic branch rewrite the last entry with the `src ::` prefix), or
buffer per-line pending entries so the post-loop fallback emits one
`(unknown) :: <pending>` entry per unrecorded failure.
