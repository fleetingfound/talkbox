# Choice: How the main-branch tree is derived from the dev commit

## context

The release script must produce a main commit whose tree equals the dev commit's tree with all `.coreignore`-matched paths removed. The repository's working tree is on `dev` and must not be disturbed (a core talkbox requirement: git operations should not affect the working tree). Two mechanisms can construct the main tree.

## options

### A. Temp-index plumbing (Recommended)

Read the dev commit's tree into a temporary index file (`GIT_INDEX_FILE`), remove the `.coreignore`-matched paths from it via `git update-index --force-remove`, write the resulting tree with `git write-tree`, and create the commit with `git commit-tree`, passing main's current HEAD as the parent. The `main` branch is then advanced with `git update-ref`. The working tree and index are never touched.

- Pros: no working-tree checkout is ever performed, so the checked-out `dev` tree and index are untouched; no risk of clobbering uncommitted dev changes; fast; uses only plumbing commands; deterministic verification (the resulting tree can be diffed against the pruned listing).
- Cons: slightly less familiar plumbing; the ignored-path list must be computed from the committed `.coreignore` (via `git check-ignore`) rather than from a live checkout.

### B. Temporary `git worktree` of `main`

Check out `main` into a temporary attached/detached worktree, apply the dev tree's filtered content there (e.g. `git archive` of the dev commit piped through a filter), commit, and remove the worktree.

- Pros: uses only familiar porcelain commands; the commit message editing happens naturally in the worktree.
- Cons: touches the filesystem with a full checkout of main; more steps to roll back on failure; the `.coreignore` filtering cannot use pathspec `git archive` exclusions with gitignore semantics directly, so the filtering still needs `git check-ignore`; heavier and slower.

## selection

Selected: **A. Temp-index plumbing** (read-tree into a temporary index, prune the .coreignore-matched paths, write-tree, commit-tree with main HEAD as parent, update-ref main).
