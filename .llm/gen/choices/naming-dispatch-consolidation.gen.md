# Choice: whether to consolidate the per-container naming dispatch (review §4)

## context

The [duplication and reusable-abstraction review](../reviews/duplication-abstraction-review.gen.md) notes that [lib/naming.sh](../../../lib/naming.sh) defines twelve near-identical one-liner functions following the `<slug>.<container>[.<kind>[.<extra>]]` pattern (container names, worktree volumes, write volumes, root images), and [lib/containers.sh](../../../lib/containers.sh) adds a second dispatch layer (`container_name_of`, `root_image_of`, `worktree_volume_of`, `write_volume_of`) plus the direct `gitdir_volume`. A single parametric `resource_name <project> <container> <kind> [extra]` could replace both layers (~16 functions → 1).

The review also labels this the **weakest candidate** in `lib/`: the named functions are self-documenting, individually unit-tested ([test/unit/naming.bats](../../../test/unit/naming.bats)), and partially intentional as the documented dispatch surface (see [MAP.gen.md](../../../MAP.gen.md)). The Phase 19 choice already decided to preserve greppable named surfaces over full parameterization (see [containers-consolidation-boundary](containers-consolidation-boundary.gen.md)).

## options

### A. Defer the naming-table consolidation (Recommended)

Leave the naming one-liners and the `*_of` dispatch layer as they are. Only the *internal* normalisation body shared between `project_slug` and `dest_slug` is extracted (a separate `slugify` phase); no dispatch-layer change.

- Pros: no loss of greppability or self-documentation; no churn in [test/unit/naming.bats](../../../test/unit/naming.bats) or the executor unit tests; consistent with the Phase 19 executor-surface-preservation decision; the review itself recommends doing this only if the naming scheme grows another dimension.
- Cons: ~16 small functions remain where 1 parametric function would do; future naming dimensions still require touching several one-liners.

### B. Introduce a parametric `resource_name`

Replace the twelve naming one-liners and the four `*_of` dispatch functions with a single parametric resource-name function (plus `gitdir_volume`), and rewrite the naming and executor unit tests against it.

- Pros: one function to extend when the scheme changes; removes the second dispatch layer.
- Cons: large test churn ([test/unit/naming.bats](../../../test/unit/naming.bats) tests each one-liner individually); loses self-documenting names at the call sites; contradicts the Phase 19 decision to keep named dispatch surfaces; no behavioural benefit.

## recommendation

Option A: the duplication is intentional and documented, the review rates it the weakest candidate, and consolidating it would re-litigate a decision already taken in Phase 19.

## decision

**Selected: Option A — defer the naming-table consolidation.** Only the shared normalisation body is extracted (Phase 20b); the per-container naming functions and `*_of` dispatch layer remain as the documented surface.
