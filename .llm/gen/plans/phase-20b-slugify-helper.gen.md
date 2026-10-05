# Phase 20b: shared slug normalisation helper in lib/naming.sh

#flow/refactor #model/default

## scope

Resolves duplication item §3 (production half) of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md).

- Implemented: extraction of the byte-identical slug normalisation body (lowercase, non-alphanumerics to hyphens, collapse runs, strip edge hyphens) shared by `project_slug` and `dest_slug` in [lib/naming.sh](../../../lib/naming.sh) into a single `slugify` helper called by both. `dest_slug` keeps its leading/trailing slash stripping as a wrapper detail.
- Deferred: the third copy, `project_slug_e2e` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash), is test-suite duplication and is out of scope for this resolution per instructions. The naming-dispatch consolidation (review §4) is deferred by the [naming-dispatch-consolidation choice](../../choices/naming-dispatch-consolidation.gen.md).

No aspect of `SPEC.md` changes; this refactors the "naming conventions" implementation. External-facing functionality is unchanged: all produced container names, volume names and image names are byte-identical.

## files to be created

None. Modified: [lib/naming.sh](../../../lib/naming.sh). Update its [MAP.gen.md](../../../MAP.gen.md) description if warranted.

## relevant files to be read

- [lib/naming.sh](../../../lib/naming.sh)
- [test/unit/naming.bats](../../../test/unit/naming.bats) (behaviour-pinning tests)

## key internal interfaces

- New `slugify` helper in [lib/naming.sh](../../../lib/naming.sh) implementing the shared normalisation; `project_slug` and `dest_slug` delegate to it. Their signatures and outputs are unchanged, and all other naming one-liners are untouched (see the deferral choice above).

## tests

Unit tests required. The existing [test/unit/naming.bats](../../../test/unit/naming.bats) tests pin `project_slug` and `dest_slug` outputs across lowercase, hyphenation, collapsing, edge-stripping and empty-result cases and must keep passing unchanged. Unit tests for `slugify` itself may be added alongside the refactor. No existing tests are superseded or removed.
