# Issue: `resolve_branches` unit test hardcodes `master` as the default branch

## Summary

The unit test `resolve_branches with --all and a remote enumerates the remote branches` fails on hosts whose `git init` default branch is `main` (the modern git default). The test setup captures the real default branch into `BRANCH` but the assertion hardcodes `master`.

## Files

- [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) — line 31

## Cause

In `test/unit/git-transport.bats`, the `setup()` function performs `git init -q "$WORK"` and stores the resulting default branch:

```bash
BRANCH="$(git -C "$WORK" symbolic-ref --short HEAD)"
```

It then pushes `HEAD` (the default branch) and `feature` to the remote `origin`.

The test `resolve_branches with --all and a remote enumerates the remote branches` (line 22) asserts that the resolved remote branches include `feature` and `master`:

```bash
[[ " ${got[*]} " == *' feature '* ]]
[[ " ${got[*]} " == *' master '* ]]   # line 31 — fails when default branch is `main`
```

On git versions where `init.defaultBranch` is `main` (git ≥ 2.28 default, and the observed environment: git 2.47.3 produces `main`), the remote branch is `origin/main`, so `resolve_branches` correctly returns `main` and `feature`. The `master` assertion therefore fails:

```
not ok 35 resolve_branches with --all and a remote enumerates the remote branches
# (in test file test/unit/git-transport.bats, line 31)
#   `[[ " ${got[*]} " == *' master '* ]]' failed
```

The implementation under test, [lib/git.sh](../../../lib/git.sh) `resolve_branches()` (lines 154–171), is correct: it delegates to `remote_branches()` which lists `refs/remotes/<remote>/*` stripped to 3 components, returning whatever the actual branch names are.

## Fix

The assertion should check for the actual default branch captured in `BRANCH` rather than the hardcoded `master`, e.g.:

```bash
[[ " ${got[*]} " == *" $BRANCH "* ]]
```

The sibling test `resolve_branches with --all and no remote enumerates the host branches` (line 34) already avoids this by only asserting against `feature` and the `expected` array built from `git for-each-ref`.

## Severity

Low — test-only defect. It produces a spurious unit-suite failure on environments whose git default branch is not `master`, with no impact on the implementation.
