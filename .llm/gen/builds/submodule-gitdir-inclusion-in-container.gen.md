# Submodule gitdirs included in the container gitdir volume

*Date: 2026-10-26*

Status: **SUCCESS**

## overview

Implemented the plan in [submodule-gitdir-inclusion-in-container.gen.md](../plans/submodule-gitdir-inclusion-in-container.gen.md): a new `include_host_modules` step in the git section of [image/setup.sh](../../../image/setup.sh) replaces `<worktree>/.git/modules` with an idempotent copy of `/host/git/modules` (stale copy made user-writable before removal), rewrites each copied module's `core.worktree` to a gitdir-relative path derived from the worktree's `.gitmodules` (`submodule.<name>.path`, with a `realpath -m --relative-to` prefix that generalises the plan's `../../../` to nested module names), and makes each module's `objects/`/`refs/` (and `packed-refs`) non-writable while leaving the module top level (notably `index`) writable. It runs in both the fresh-init and existing-repository branches, guarded on `/host/git/modules` existing and being non-empty. [MAP.gen.md](../../../MAP.gen.md) updated the `image/setup.sh` entry; no other core file changed (`lib/git.sh` untouched).

## verification

- `make lint` and `make format`: green
- `make test-unit`: `total=307 pass=307 fail=0 skip=0 exit=0`
- `make test-e2e`: `total=81 pass=81 fail=0 skip=0 exit=0`

The e2e coverage includes the plan's cases: submodule reads succeed while submodule history writes (`update-ref`, `commit`) fail with permission errors; superproject `git status`/`git add -A --dry-run` succeed with an absorbed submodule and dirtiness is tracked (` M sub`); the container resolves an absorbed module gitdir against the container submodule path (including a name≠path module with a host-planted absolute `core.worktree`); and the modules tree refreshes from the host on every setup run.

## dispute resolution

The e2e suite initially reported 79/81 pass: the two revised submodule tests asserted exact/empty `$output` captures that the SPEC-mandated `sdrun` harness makes unsatisfiable. [The dispute document](../disputes/submodule-tests-assert-noise-free-output.gen.md) was resolved by [the verdict document](../verdicts/submodule-tests-assert-noise-free-output.gen.md), which found both tests `BROKEN_TEST` and prescribed marker-adjacency/`grep -Fxq` assertion repairs; those repairs are applied in [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats) and both tests now pass. The dispute and verdict are marked complete in their indexes.

## resolution

This resolves [the dangling-gitfile issue](../issues/submodule-gitfile-dangling-in-container.gen.md) (marked complete in the issues index). The plan is marked complete in the plans index.
