# Submodule gitdirs in the container: fix the dangling gitfile and prevent submodule writes

#flow/redgreen #model/default

## Aspects of the specification implemented

- SPEC.md "Submodules are supported. When `onbox`, `netbox` or `offbox` are used to create a container, the submodules are absorbed into the host's top-level git directory **and then included in the container**." — the second half (inclusion in the container gitdir volume) is currently unimplemented, which this plan implements.
- SPEC.md "git operations within a submodule are prevented within the container and must be made on the host instead" — reimplemented as targeted write prevention (reads succeed, history writes fail) so that superproject-level git operations work.

Deferred: nothing else. No changes to host-side absorption (`absorb_submodules` in `lib/git.sh`), to the git transport (`fetch`/`merge`/`sync`), or to worktree population.

## External-facing functionality

- Superproject-level `git status`, `git diff`, `git add -A` and similar index/commit operations inside the container no longer fatal when the project contains a submodule checkout; submodule state is accurately summarized (dirtiness tracked against the host's submodule history).
- Submodule-level *history-writing* git operations (`commit`, `add`, `update-ref`, `tag`, …) inside the container fail with permission errors, while submodule *reads* (`git -C <sub> status`, `log`) work — enforcement is by non-writable `objects/` and `refs/` in the copied module gitdirs.
- The modules tree is refreshed from `/host/git/modules` on every setup run (idempotent replace), so host-side submodule changes propagate into the container gitdir on each container creation/recontain.

## Implementation outline

### 1. `image/setup.sh` — module inclusion step

New function in the git section (after `ensure_host_remote`/fresh-init wiring, running in *both* the fresh-init and existing-repository branches, guarded on `/host/git/modules` existing and being non-empty):

- Replace `<worktree>/.git/modules` with a copy of `/host/git/modules` (remove the previous copy first so host-side submodule changes propagate; `chmod -R u+w` the stale copy before removal since its `objects/`/`refs/` were made non-writable, or copy over it accordingly).
- Rewrite each copied module's `core.worktree` to a path relative to that module's gitdir (`../../../<submodule-path>`), resolving `<submodule-path>` from the worktree's `.gitmodules` (`submodule.<name>.path` → `modules/<name>`); leave a module whose name has no `.gitmodules` entry untouched.
- Make `objects/` and `refs/` (and `packed-refs`, if present) non-writable in each copied module, leaving the module top level (notably `index`) writable so superproject status can refresh the submodule index.

### 2. `test/e2e/git-transport.bats` — test revision

- Supersede the existing "git operations inside a submodule are blocked within the container" test: it currently asserts `git -C sub status` *fails*, which passes only because the gitdir is missing. It is replaced by assertions that `git -C <sub> status` (read) *succeeds* while a submodule history write (`git -C <sub> update-ref` or an empty commit) *fails* on the non-writable `objects/`/`refs/`.
- New test: superproject-level `git status` (and `git add -A --dry-run` or `git diff --stat`) succeeds in the container for a project with an absorbed submodule, including when the index contains the gitlink (the container index is populated by the initial `reset --mixed`).

## Files to create

None. Files modified:

- [image/setup.sh](image/setup.sh) — module-inclusion step (copy, `core.worktree` rewrite, targeted read-only permissions) in the git section.
- [test/e2e/git-transport.bats](test/e2e/git-transport.bats) — supersede the submodule test, add the superproject-status test.
- [MAP.gen.md](MAP.gen.md) — update the `image/setup.sh` entry (and nothing else; `lib/git.sh` is unchanged).

## Files to read during implementation

- [image/setup.sh](image/setup.sh) — current git section structure and the fresh-init/existing-repository branches.
- [lib/git.sh](lib/git.sh) — `absorb_submodules`/`plan_git_mounts` (context only; unchanged).
- [test/e2e/git-transport.bats](test/e2e/git-transport.bats) and [test/e2e/helpers.bash](test/e2e/helpers.bash) — e2e harness conventions (`run_talkbox`, `run_onbox_noninteractive`, temp remote/project setup).
- [lib/naming.sh](lib/naming.sh) — gitdir-volume naming (context for `/working/<project-base>/.git` volume mount).
- `.llm/gen/choices/submodule-modules-inclusion-mechanism.gen.md` and `.llm/gen/choices/submodule-write-prevention-in-container.gen.md` — the selected designs.

## Key internal interfaces

- `image/setup.sh` internal helper (bash function) implementing the module inclusion: takes the worktree repo path and `/host/git/modules` as inputs; performs copy → `core.worktree` rewrite → targeted `chmod`; idempotent across setup reruns on a persistent gitdir volume.
- No new interfaces in `lib/`; the host-side absorption and container planners are untouched.

## Tests

- E2E (in [test/e2e/git-transport.bats](test/e2e/git-transport.bats)): the two cases above (superproject status succeeds; submodule write prevented, submodule read works). These exercise the full host→container pipeline including the gitdir volume, `setup.sh` and the host `absorb_submodules`, so no separate unit tests are required; the setup step runs inside the container and has no unit-testable shell surface in `lib/`.
- ShellCheck/`make lint`/`make format` coverage of the `setup.sh` change per repository conventions.
