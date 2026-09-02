# Tests: Phase 8d `resolve_branches` test must not hardcode `master`

Linked plan: [phase-8d-git-transport-test-default-branch.gen.md](../plans/phase-8d-git-transport-test-default-branch.gen.md)

Summary: this phase replaces the hardcoded `master` assertion in the `resolve_branches with --all and a remote enumerates the remote branches` unit test with an assertion against the actual default branch captured in `BRANCH` by `setup()`, so the test passes on hosts whose `git init` default branch is `main` as well as those defaulting to `master` — resolving [git-transport-test-hardcodes-master-branch.gen.md](../issues/git-transport-test-hardcodes-master-branch.gen.md); no implementation behaviour changes.

## New tests

- None. The plan is a single-line assertion fix to an existing unit test; no new test case is introduced.

## Tests edited

- `test/unit/git-transport.bats` — `resolve_branches with --all and a remote enumerates the remote branches` (line 31): the assertion `[[ " ${got[*]} " == *' master '* ]]` is replaced with `[[ " ${got[*]} " == *" $BRANCH "* ]]`.
  - How it fails against the current implementation: on hosts where `git init` creates a `main` default branch (git ≥ 2.28, including the observed git 2.47.3), `resolve_branches` correctly returns the remote branches `main` and `feature`, so the hardcoded `master` membership check fails with `` `[[ " ${got[*]} " == *' master '* ]]' failed `` at line 31 even though the implementation is correct. The new assertion uses `$BRANCH`, captured from `git symbolic-ref --short HEAD` in `setup()` (line 12), which is the actual default branch pushed to the `origin` remote, matching the pattern already used by the sibling test `resolve_branches without a branch defaults to the current branch` (line 59).
  - The `expected` array equality check (line 29) and the `feature` membership check (line 30) are unchanged and already pass on both `master` and `main` hosts.

## Tests removed

- None. No test is removed or inconsistent with the plan; the only defect is the single hardcoded `master` assertion fixed above.
