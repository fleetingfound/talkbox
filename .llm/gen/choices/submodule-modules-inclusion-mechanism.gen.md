# Submodule `modules/` inclusion mechanism for the container gitdir

## Context

After `absorb_submodules()` absorbs each submodule's git directory into the host superproject's `.git/modules/<name>/`, the worktree gitfile `<sub>/.git` points relatively at `../.git/modules/<name>`. Inside the container the superproject `.git` is the gitdir volume (a fresh `git init`), so the pointer dangles and superproject `git status`/`git diff`/`git add -A` fatals. SPEC.md requires that absorbed submodules are "included in the container". The mechanism for making the gitfile target reachable must also cope with the fact that `git submodule absorbgitdirs` records an **absolute host path** in each module's `core.worktree`, which is invalid inside the container (worktree lives at `/working/<project-base>`).

## Option A (Recommended): Copy `modules/` into the gitdir volume in `setup.sh`

`image/setup.sh` gains a module-inclusion step (run in both the fresh-init and existing-repository branches, whenever `/host/git/modules` exists):

- copy `/host/git/modules` into `<worktree>/.git/modules`, replacing any previous copy so host changes propagate on each container start
- rewrite each copied module's `core.worktree` to a path relative to the module gitdir (i.e. `../../../<submodule-path>`), derived from the worktree's `.gitmodules` name→path mapping, so the container worktree resolves correctly for onbox (bind) and netbox/offbox (volume) alike
- apply targeted read-only permissions (see companion choice) to enforce SPEC's "submodule operations are prevented"

Pros: works for all three containers via the single shared `setup.sh`; the container copy is mutable enough to fix `core.worktree`; refreshes from the host on every setup run; no planner/mount changes in `lib/git.sh`/`lib/containers.sh`; module refs/objects never leak into the bundle (bundle is built from the top-level gitdir only).

Cons: duplication of the host `modules/` tree into the volume (disk cost); staleness until the next setup run.

## Option B: Read-only bind-mount of the host `modules/` at `/working/<base>/.git/modules`

Mount `<host-gitdir>/modules` over the gitdir-volume path `/working/<base>/.git/modules` in `plan_git_mounts`/`plan_container`.

Pros: always host-fresh; no volume copy.

Cons: mount-order coupling with the gitdir volume mount; and critically, `core.worktree` in the mounted configs points at the host path, which is not writable/valid inside the container and cannot be rewritten (the mount is read-only), so submodule status operations resolve the wrong worktree and superproject status still misbehaves.

## Option C: Do not include modules; neutralize descent instead

Configure the container repo (e.g. `submodule.<name>.active=false` or `diff.ignoreSubmodules`) so superproject status/diff skip descending into submodules.

Pros: minimal, no copies.

Cons: contradicts SPEC's "absorbed ... and then included in the container"; leaves `git add <submodule-path>` / direct submodule operations fatalling on the dangling gitfile; status reports submodule dirtiness incorrectly (degraded, not accurate).

## Decision

**Option A selected** (copy `modules/` into the gitdir volume in `setup.sh`, rewriting `core.worktree` per module). Copy-into-gitdir-volume with targeted read-only protection chosen over the bind-mount and config-neutralization options.
