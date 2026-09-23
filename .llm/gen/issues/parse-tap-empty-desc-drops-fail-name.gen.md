# `parse_tap()` drops failing tests with empty descriptions from `FAIL_NAMES`

## Summary

In `parse_tap()`, the `FAIL` counter is incremented for every `not ok` line, but
a failing test whose TAP description parses to an empty string is never appended
to `FAIL_NAMES`. The result is `len(FAIL_NAMES) < FAIL`, so the run record's
`fail:` list is incomplete and silently omits some failing tests.

## Affected files

- [test/lib.bash](test/lib.bash) — `parse_tap()` (the `'not ok '*` branch and
  both append sites guarded by `[[ -n "$pending" ]]`).

## Root cause

The `'not ok '*` branch derives the test name into `pending` as:

```bash
local desc="${line#not ok }"   # "<num> <desc> [# <directive>]"
desc="${desc#* }"              # "<desc> [# <directive>]"
desc="${desc% # *}"            # "<desc>"
pending="$desc"
```

When the test has an empty description, bats 1.11 emits lines such as:

```
not ok 1
# (in test file empty.bats, line 2)
```

or, for an empty-named test that times out:

```
not ok 1  # timeout after 1s
# (in test file empty_timeout.bats, line 2)
```

In both cases `${desc#* }` strips the number token and leaves the empty
description (the `${desc% # *}` directive strip then also yields `""`), so
`pending` is set to the empty string.

Both sites that append to `FAIL_NAMES` guard on a non-empty `pending`:

- the `# (in test file` / `#  in test file` diagnostic branch (`if [[ -n "$pending" ]]`)
- the post-loop fallback that emits `(unknown) :: $pending` (`if [[ -n "$pending" ]]`)

Because `pending` is empty, neither guard passes, so no entry is created even
though `FAIL` was already incremented.

## Consequences

- A single empty-named failing test produces `FAIL=1` with an empty `fail:`
  list in the run record (verified: `test/...empty.bats` → `FAIL=1 FAIL_NAMES=0`).
- In a multi-failure suite, empty-description failures are silently dropped
  while named failures are recorded (verified: 2 failures, one empty-named →
  `FAIL=2 FAIL_NAMES=1`). The `FAIL` counter and `fail:` list disagree.

## Reproduction

```bash
cat > /tmp/empty.bats <<'EOF'
@test "" { false; }
EOF
bats --tap /tmp/empty.bats > /tmp/empty.tap 2>/dev/null
PROJECT_ROOT="$PWD" source test/lib.bash
parse_tap /tmp/empty.tap
echo "FAIL=$FAIL FAIL_NAMES=${#FAIL_NAMES[@]}"   # FAIL=1 FAIL_NAMES=0
```

## Suggested fix direction

Do not gate appending on `[[ -n "$pending" ]]`. When the description is empty,
substitute a placeholder (e.g. `(unnamed)`) for `pending` in the `'not ok '*`
branch so the diagnostic branch and the post-loop fallback both record an entry,
keeping `len(FAIL_NAMES) == FAIL`.
