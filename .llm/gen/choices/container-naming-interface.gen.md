# Choice: the post-consolidation naming interface

*Date: 2026-10-09*

## context

[lib/naming.sh](../../../lib/naming.sh) defines 9 per-container one-liners following the `<project-slug>.<container>[.<kind>[.<qualifier>]]` pattern, and [lib/containers.sh](../../../lib/containers.sh) adds a dispatch layer over them (`container_name_of`, `root_image_of`, `worktree_volume_of`, `write_volume_of`) plus the already-generic `gitdir_volume`. The [common-implementation review](../reviews/container-common-implementation.gen.md) notes that every name is derivable from the container string itself, so the dedicated layer can collapse. A prior choice ([naming-dispatch-consolidation scope](naming-dispatch-consolidation.gen.md)) deferred this consolidation; it is now in scope. `worktree_volume_of` for `onbox` returns the host project path (onbox's worktree is a bind mount, not a volume) — a degenerate mapping that must survive in some form.

## options

### A. Keep the four `*_of` dispatchers, implemented generically (Recommended)

Keep `container_name_of`, `root_image_of`, `worktree_volume_of` and `write_volume_of` with their current names and signatures, but implement each as a generic one-liner over the container argument (`<project-slug>.<container>[.<kind>[.<qualifier>]]`); delete the 9 dedicated one-liners. `worktree_volume_of` retains the onbox degenerate mapping to the host project path.

- Pros: zero call-site churn across `lib/` and `talkbox.sh`; the dispatcher names are self-documenting; unit tests exercising the dispatchers survive unchanged, minimising the test-suite revision the consolidation phase requires.
- Cons: four functions where one parametric helper would do; the onbox worktree degenerate mapping keeps a semantic special case inside a naming function.

### B. One generic resource-name helper

Replace both layers with a single parametric helper (e.g. `container_name <project> <container> [kind] [qualifier]`), as the review sketches.

- Pros: a single function to extend when the naming scheme grows.
- Cons: less self-documenting call sites; churn in every call site and in the unit tests; loses the greppable named surface that Phase 19 deliberately preserved.

### C. Keep the 9 dedicated one-liners

Leave `lib/naming.sh` untouched.

- Pros: no churn at all.
- Cons: leaves ~27 lines of dedicated per-container code plus the dispatch layer, contradicting the consolidation's goal of per-container knowledge living only in configuration.

## recommendation

Option A: it removes all per-container dedication from the naming layer with minimal churn, and because the `*_of` dispatchers already form the container-parameterised surface that everything (including the tests) consumes, it keeps the consolidation's test revision small.

## decision

**Selected: Option A — keep the four `*_of` dispatchers, implemented generically.**
