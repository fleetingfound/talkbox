# Review: Causes of failing tests

## scope

This review identifies and explains the cause of every failing test observed when running `make test-unit` and `make test-e2e` against the current tree (git 2.47.3, default branch `main`; podman available).

## findings

### unit suite — 1 genuine failure (test defect)

`make test-unit` reports `total=178 pass=177 fail=1`:

```
not ok 35 resolve_branches with --all and a remote enumerates the remote branches
# (in test file test/unit/git-transport.bats, line 31)
#   `[[ " ${got[*]} " == *' master '* ]]' failed
```

**Cause:** the test setup runs `git init -q "$WORK"` and captures the real default branch into `BRANCH`, but the assertion at [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) line 31 hardcodes `master`. On git versions whose `init.defaultBranch` is `main`, the remote branch is `origin/main`, so the implementation ([lib/git.sh](../../../lib/git.sh) `resolve_branches()`) correctly returns `main` and `feature`, and the `master` assertion fails. The implementation is correct; this is a test-only defect. See the open issue [git-transport-test-hardcodes-master-branch](../issues/git-transport-test-hardcodes-master-branch.gen.md), also linked from [git-transport-review](git-transport-review.gen.md).

The sibling test `resolve_branches with --all and no remote enumerates the host branches` is not affected because it asserts only against `feature` and an `expected` array built from `git for-each-ref`.

### e2e suite — 0 genuine failures (environmental)

`make test-e2e` initially reported `total=60 pass=59 fail=1`:

```
not ok 44 netbox --rm-image removes the base image
# (in test file test/e2e/netbox-offbox.bats, line 169)
#   `[[ "$status" -eq 0 ]]' failed
```

**Cause:** environmental, not a code or test defect. `run_netbox_rm_image()` ([lib/containers.sh](../../../lib/containers.sh) lines 776–787) calls `image_in_use` (lines 170–180) which refuses `podman rmi talkbox/base:latest` when any container other than the current project's netbox container uses the shared base image as an ancestor. The shared base image is global across all projects, so orphan containers left behind by an interrupted prior e2e run (in this case, the first `make test-e2e` invocation that was terminated by the tool timeout) cause `image_in_use` to return true and the command to die with `cannot remove base image: it is in use by other containers`.

After removing the orphan containers/images/volumes left by the interrupted run, the full e2e suite passes cleanly: `total=60 pass=60 fail=0 exit=0`. Running `bats test/e2e/netbox-offbox.bats` in isolation also passes all 13 tests including test 44.

## observation — e2e orphan-container fragility

The e2e `teardown()` in [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) (lines 14–22) removes only containers/images/volumes whose names match the current `$PROJECT_SLUG`. An interrupted e2e run therefore leaves orphan containers behind, and because the base image `talkbox/base:latest` is shared and `--rm-image` refuses to remove an in-use image, a subsequent run's `netbox --rm-image removes the base image` test breaks until the orphans are manually cleaned. This is a harness-hygiene fragility rather than an implementation bug — `image_in_use`'s refusal is correct and desirable behaviour for a shared base image. A global cleanup step (or building the base image under a unique tag per e2e run) would make the suite self-contained.

## verdict

- The only genuine failing test is `test/unit/git-transport.bats` test 35, a test-only defect from hardcoding `master`. Fix documented in [git-transport-test-hardcodes-master-branch](../issues/git-transport-test-hardcodes-master-branch.gen.md).
- The e2e failure in test 44 is environmental (orphan containers from an interrupted prior run) and disappears in a clean environment; the full e2e suite passes 60/60.
