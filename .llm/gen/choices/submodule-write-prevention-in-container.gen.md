# Enforcement of "submodule git operations are prevented" in the container

## Context

Once the absorbed `modules/<name>` gitdirs are reachable in the container (see companion choice), submodule-level git *reads* must work so superproject `git status`/`git diff`/`git add -A` can descend into gitlinks. SPEC also requires that "git operations within a submodule are prevented within the container and must be made on the host instead". The existing e2e test (`git -C sub status` must fail) passes today only accidentally — because the gitdir is missing — and must be tightened per the issue.

## Option A (Recommended): Targeted read-only protection — module `objects/` and `refs/` (and `packed-refs`) non-writable

After copying `modules/` into the gitdir volume, remove write permission from each copied module's `objects/` and `refs/` (and `packed-refs`) while leaving the module gitdir top level (notably `index`, so superproject status can refresh the submodule index) writable.

Pros: superproject operations work (index refreshes survive); submodule history-changing operations (`git -C sub add`, `commit`, `branch`, `update-ref`, `tag`) fail with permission errors because they must write objects or refs; module history cannot diverge from the host's, so nothing submodule-related leaks back via the bundle (the bundle also only packs top-level repo refs anyway).

Cons: enforcement is by filesystem permissions, so it is advisory (the user owns the files and can chmod back) — but the container's whole trust model already treats `dev` as the user, so this matches the threat model; index-only submodule operations (e.g. `git -C sub rm --cached`) remain possible.

## Option B: No enforcement — fully working submodule gitdirs

Copy the modules tree as-is and let all submodule git operations succeed.

Pros: simplest; container submodule history is writable.

Cons: contradicts SPEC ("submodule operations ... must be made on the host instead"); container submodule commits would be stranded in the gitdir volume's `modules/` (invisible to the bundle fetch) and silently lost on `--recontain` volume recreation.

## Option C: Fully read-only modules

`chmod -R a-w` the whole `modules/` copy.

Cons: superproject `git status` may itself fail when git tries to refresh the submodule index (`index.lock` cannot be created), reintroducing a variant of the current bug.

## Decision

**Option A selected** (targeted read-only `objects/`/`refs`/`packed-refs` in the copied modules; index and reads stay writable/functional).
