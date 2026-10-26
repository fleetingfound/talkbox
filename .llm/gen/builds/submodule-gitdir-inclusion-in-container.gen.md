# Submodule gitdirs included in the container gitdir volume

*Date: 2026-10-26*

Status: **BLOCKED**

## overview

Implemented the plan in [submodule-gitdir-inclusion-in-container.gen.md](../plans/submodule-gitdir-inclusion-in-container.gen.md): a new `include_host_modules` step in the git section of [image/setup.sh](../../../image/setup.sh) replaces `<worktree>/.git/modules` with an idempotent copy of `/host/git/modules` (stale copy made user-writable before removal), rewrites each copied module's `core.worktree` to a gitdir-relative path derived from the worktree's `.gitmodules` (`submodule.<name>.path`, with a `realpath -m --relative-to` prefix that generalises the plan's `../../../` to nested module names), and makes each module's `objects/`/`refs/` (and `packed-refs`) non-writable while leaving the module top level (notably `index`) writable. It runs in both the fresh-init and existing-repository branches, guarded on `/host/git/modules` existing and being non-empty. [MAP.gen.md](../../../MAP.gen.md) updated the `image/setup.sh` entry; no other core file changed (`lib/git.sh` untouched).

## verification

- `make test-unit`: 307/307 pass
- `make test-e2e`: 79/81 pass
- `shellcheck image/setup.sh` and `shfmt -d image/setup.sh`: green

The passing submodule e2e coverage: submodule reads succeed while submodule history writes (`update-ref`, `commit`) fail with permission errors; the modules tree refreshes from the host on every setup run; the dirt-check phase (`git status --porcelain` reporting ` M sub`) and the behaviour asserted by the two blocked tests were additionally demonstrated correct via isolated replicas of the test bodies.

## blocked on

Two of the plan's revised e2e tests assert on the entirety of `$output` (`[[ -z "$output" ]]` and exact equality), which the SPEC-mandated `sdrun`/bats harness makes unsatisfiable: `systemd-run --pipe --wait` prints unit-lifecycle lines to stderr, bats `run` folds stderr into `$output`, and first-run `podman volume create`/`create`/`start` stdout adds volume/container names. Captures show the asserted behaviour holding with only harness noise around it. Full details and suggested substring-style fixes: [the dispute document](../disputes/submodule-tests-assert-noise-free-output.gen.md), summarised here in one sentence — the two tests in test/e2e/git-transport.bats use exact/empty output assertions inconsistent with the harness noise floor that every other test in the suite accommodates via substring matching.

## resolution

This resolves [the dangling-gitfile issue](../issues/submodule-gitfile-dangling-in-container.gen.md) (marked complete in the issues index). The plan stays unchecked in the plans index pending resolution of the dispute.
