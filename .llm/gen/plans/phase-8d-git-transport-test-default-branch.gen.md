# Plan: Phase 8d — `resolve_branches` test must not hardcode `master`

#flow/pin #model/default

## Specification scope

This is a test-quality fix, not a feature change. No aspect of `SPEC.md` / `SPEC.gen.md` is altered and no implementation behaviour changes. It resolves the open issue [`resolve_branches` unit test hardcodes `master` as the default branch](../issues/git-transport-test-hardcodes-master-branch.gen.md).

The implementation under test (`resolve_branches` in [lib/git.sh](../../../lib/git.sh)) is correct: it returns whatever branch names actually exist. Only the test assertion is wrong.

## To be implemented

In the `resolve_branches with --all and a remote enumerates the remote branches` test in [test/unit/git-transport.bats](../../../test/unit/git-transport.bats), replace the hardcoded `master` assertion on line 31 with an assertion against the actual default branch captured in `BRANCH` by `setup()`:

- Change `[[ " ${got[*]} " == *' master '* ]]` to assert that the resolved remote branches include `"$BRANCH"`, matching the pattern already used by the sibling test `resolve_branches without a branch defaults to the current branch` (line 59) and by `resolve_branches with --all and no remote enumerates the host branches` which only asserts against `feature` and the `expected` array built from `git for-each-ref`.

No other assertions in the test change: the `expected` array equality check (line 29) and the `feature` membership check (line 30) remain as-is and already pass on both `master` and `main` hosts.

## To be deferred

- Nothing. This is a self-contained, single-line test fix.

## External-facing functionality

None — no user-facing behaviour changes. Only a unit test assertion changes.

## Files to be created

- None.

## Files to read during implementation

- [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) — the test containing the hardcoded `master` assertion (line 31) and the `setup()` that captures `BRANCH` (line 12).
- [lib/git.sh](../../../lib/git.sh) `resolve_branches` / `remote_branches` — confirms the implementation is correct and the test is the sole defect.

## Key internal interfaces

- None modified. The `BRANCH` shell variable is already populated by `setup()` and is in scope for every test in the file.

## Tests

This plan *is* a test change. The relevant test is the unit case itself:

- **Unit tests:** the `resolve_branches with --all and a remote enumerates the remote branches` case in `test/unit/git-transport.bats` must pass on hosts whose `git init` default branch is `main` (the modern git default, e.g. git ≥ 2.28) as well as hosts still defaulting to `master`. Run the full `test/unit/git-transport.bats` suite to confirm no regressions in sibling tests.
- **End-to-end tests:** none required — this is a unit-test-only fix with no implementation change.
