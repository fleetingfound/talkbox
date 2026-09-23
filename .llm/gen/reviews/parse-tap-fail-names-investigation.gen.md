# `parse_tap()` name-recording investigation

## Question

> In some cases `parse_tap()` fails to append a name to `FAIL_NAMES`, even if
> the `FAIL` counter is incremented. Investigate.

## Scope

- [test/lib.bash](test/lib.bash) — `parse_tap()` and `write_record()`.
- [test/run-suite.sh](test/run-suite.sh) — caller; invokes `parse_tap` on the
  bats `--tap` output and writes the run record via `write_record`.

bats version in this environment: **Bats 1.11.1**.

## How `parse_tap` records a failing test

The `'not ok '*` branch increments `TOTAL`/`FAIL` and derives the test name
into `pending`:

```bash
local desc="${line#not ok }"   # "<num> <desc> [# <directive>]"
desc="${desc#* }"              # "<desc> [# <directive>]"
desc="${desc% # *}"            # "<desc>"
pending="$desc"
```

A name is appended to `FAIL_NAMES` in one of two places, **both guarded by
`[[ -n "$pending" ]]`**:

1. The diagnostic branch matching `# (in test file ` or `#  in test file `
   (the latter is the bats 1.11 helper-function continuation line — see
   [Phase 4](../tests/phase-4-git-integration-fetch.gen.md)).
2. The post-loop fallback that emits `(unknown) :: $pending` when the loop ends
   with unconsumed `pending` (e.g. bats was killed mid-output).

## Findings

### Diagnostic-line formats all match (no longer a source of loss)

Real bats 1.11 output was collected for every failure flavour:

| Failure flavour | Diagnostic line(s) | Matched? |
|---|---|---|
| Simple assertion | `# (in test file …, line N)` | yes (`# (in test file `) |
| `exit`/`return`/external command | `# (in test file …, line N)` | yes |
| Helper function (single level) | `# (from function …` then `#  in test file …, line N)` | yes (`#  in test file `) |
| Nested helpers | `# (from function …` (×N) then `#  in test file …, line N)` | yes |
| Sourced-lib function | `# (from function …` then `#  in test file …` | yes |
| Timeout (`# timeout after Ns`) | `# (in test file …, line N)` | yes |

So the diagnostic-matching patterns are complete for bats 1.11.1; the
previously missing `#  in test file` pattern was already added by Phase 4.

### The real loss: empty test descriptions

When a test has an empty/blank description (bats `@test ""`), bats emits:

```
not ok 1
# (in test file empty.bats, line 2)
```

or, for an empty-named test that times out:

```
not ok 1  # timeout after 1s
# (in test file empty_timeout.bats, line 2)
```

Tracing the `pending` derivation:

- `${line#not ok }` → `1 ` (or `1  # timeout after 1s`)
- `${desc#* }` strips up to the first space → `""` (the description is empty)
- `${desc% # *}` → `""`
- `pending=""`

Because `pending` is the empty string, **both** `[[ -n "$pending" ]]` guards
fail, so no `FAIL_NAMES` entry is created — while `FAIL` was already
incremented.

Verified directly:

```
empty.bats          → FAIL=1 FAIL_NAMES=0
empty_timeout.bats  → FAIL=1 FAIL_NAMES=0
multi.bats (empty-named + named failure) → FAIL=2 FAIL_NAMES=1
```

In the multi-failure case the empty-named failure is silently dropped and only
the named failure appears in `fail:`.

## Conclusion

The reported symptom has a single root cause: a `not ok` line whose description
parses to `""` sets `pending=""`, and the non-empty guard on both append sites
suppresses the entry. The diagnostic-line patterns are otherwise complete for
bats 1.11.1, so this is the remaining case where `FAIL` and `len(FAIL_NAMES)`
diverge.

The bug, its reproduction, and a suggested fix direction are recorded in
[parse-tap-empty-desc-drops-fail-name](../issues/parse-tap-empty-desc-drops-fail-name.gen.md).
