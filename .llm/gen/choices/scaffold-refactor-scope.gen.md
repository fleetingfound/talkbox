# Choice: Scaffold refactor scope

## Context

[Review: Phase 1 onbox implementation as a scaffold](../reviews/phase-1-onbox-scaffold.gen.md) identifies 8 significant shortcomings in the Phase 1 implementation as a scaffold for Phases 2-5, plus several style/minor issues. The review is explicit that none of these block Phase 1 correctness — they are forward-looking improvements. This choice determines how many of the review's recommendations to address in a dedicated scaffold-refactor phase before Phase 2.

The 8 recommendations are:

1. Replace the text-protocol planner with an array-populating planner (nameref or NUL-delimited).
2. Factor `run_onbox` into a lifecycle-aware executor with image/container/volume operation seams.
3. Restructure `plan_onbox` as shared base args + container-specific overrides.
4. Introduce stub `lib/mounts.sh` and `lib/ports.sh` seams (trivial bodies the planner calls).
5. Generalize `options.sh` to a single structured parser, dropping the `ONBOX_` prefix.
6. Keep the planner's filesystem checks at emit time; pass pre-parsed data as arguments (a principle to preserve, not a standalone change).
7. Add `root_image_name()` and an image-operations seam (`lib/images.sh`).
8. Make `--rm` a planner input, not a constant.

Style/minor issues: remove shebangs from sourced `lib/*.sh` files; add a `die()` helper for error messages; `entrypoint.sh` `exec "$@"` instead of `exec bash -c "$*"`; make the global-dotfiles mount conditional on existence; clean up the `load_lib` "not implemented yet" fallback.

## Options

### Option A — Phase 2-focused scaffold (Recommended)

Address the recommendations that directly make Phase 2 additive, plus low-risk de-specialization of Phase 3-oriented items:

- **Rec 1** (array-populating planner) — the highest-value refactor; eliminates the fragile text protocol.
- **Rec 2** (lifecycle-aware executor seams) — separate image/container/volume operation surfaces; only the `run` verb is implemented, but the shape anticipates `--recontain`/`--rebuild`/`--rm-*`.
- **Rec 4** (stub `lib/mounts.sh` and `lib/ports.sh`) — trivial stub bodies (e.g. emit the hardcoded worktree/dotfiles mounts, emit the bare `pasta` network option) that the planner calls; Phase 2 replaces stub bodies with real parsing.
- **Rec 8** (`--rm` as a planner input) — small change enabled by rec 1.
- **Rec 5 (partial)** — drop the `ONBOX_` prefix and rename `parse_onbox_options` to a container-agnostic `parse_options`; keep the scalar global model (lists for `--read`/`--write`/`--port` deferred to Phase 2 where they are concretely needed).
- **Rec 7 (partial)** — add `root_image_name()` to `lib/naming.sh` as a stub returning the shared base image name for now (Phase 3 overrides it). Defer the `lib/images.sh` module to Phase 3 where `podman commit` and `--rm-image` in-use detection are actually implemented.
- **All style/minor fixes.**

Defer:
- **Rec 3** (shared base + container-specific overrides) to Phase 3. Although SPEC.md defines the shared-vs-differing surface, the exact factoring is best validated against a concrete second container (`netbox`); doing it now risks a misfit abstraction that Phase 3 must undo.
- **Rec 5 (full structured-record-with-lists)** to Phase 2, where repeatable `--read`/`--write`/`--port` provide the concrete pressure for list-valued fields.
- **Rec 7 (image-operations module)** to Phase 3.

**Pros:** addresses the single most impactful issue (text protocol) and the items Phase 2 directly needs; avoids speculative Phase 3 abstractions; moderate, well-scoped refactor.
**Cons:** Phase 3 still has structural work (shared base extraction, full option-record redesign, image module) — but done with concrete containers to validate.

### Option B — Full scaffold (all 8 recommendations)

All 8 recommendations plus style fixes, in one or two phases.

**Pros:** maximum forward-looking improvement; Phase 2 and Phase 3 both become largely additive.
**Cons:** rec 3 designs the shared/override split without a concrete second container (risk of misfit); rec 5's full structured-record overlaps heavily with Phase 2's option parsing (risk of designing the record shape before the repeatable flags are concrete); rec 7's `lib/images.sh` is an empty shell until Phase 3; larger surface to review and verify.

### Option C — Minimal scaffold

Rec 1 (array planner) + rec 8 (`--rm` input) + style fixes only.

**Pros:** smallest change; lowest risk; fixes the single highest-value issue.
**Cons:** Phase 2 still needs to refactor the executor for lifecycle verbs, create `lib/mounts.sh`/`lib/ports.sh` from scratch (rather than replacing stubs), and generalize `options.sh`; less of Phase 2 is additive.

## Recommendation

**Option A.** It captures the review's two highest-value recommendations (array planner, lifecycle executor seams), foreshadows the Phase 2 module seams (stub mounts/ports), and removes the most obvious premature specialization (ONBOX_ prefix, root_image_name stub) at low risk, while deferring the genuinely speculative Phase 3 abstractions to where concrete containers validate them.

## Selected option

**Option C (Minimal scaffold).** Selected by the user. The scaffold-refactor phase addresses only: rec 1 (array-populating planner via nameref), rec 8 (`--rm` as a planner input), and the style/minor fixes (remove shebangs from sourced `lib/*.sh`, add a `die()` helper, `entrypoint.sh` `exec "$@"`, make the global-dotfiles mount conditional on existence, clean up `load_lib`'s "not implemented yet" fallback). All other recommendations (rec 2 lifecycle executor seams, rec 3 shared-base split, rec 4 stub mounts/ports, rec 5 generalized options parser, rec 7 image seam) are deferred to their natural phases where concrete requirements validate them.

## Related

- [Review: Phase 1 onbox implementation as a scaffold](../reviews/phase-1-onbox-scaffold.gen.md)
- [Choice: Module Structure](module-structure.gen.md)
- [Choice: Test Modularization](test-modularization.gen.md)
- [Choice: Planner-vs-executor project-dotfiles existence handling](planner-dotfiles-existence.gen.md)
