# Tests: Phase 20b — shared slug normalisation helper in lib/naming.sh

Linked plan: [phase-20b-slugify-helper.gen.md](../plans/phase-20b-slugify-helper.gen.md)

Summary: the plan extracts the byte-identical slug normalisation body (lowercase, non-alphanumerics to hyphens, collapse runs, strip edge hyphens) shared by `project_slug` and `dest_slug` in [lib/naming.sh](../../../lib/naming.sh) into a single `slugify` helper called by both, with all produced container, volume and image names unchanged, so this pinning pass keeps every existing test in [test/unit/naming.bats](../../../test/unit/naming.bats) unchanged and adds the slug-normalisation coverage the plan attributes to them but that was missing — edge-stripping and empty-result pins for `project_slug`, collapsing/edge-stripping/empty-result pins for `dest_slug`, and a pin that both functions normalise the same string identically, which is precisely the property the `slugify` extraction must preserve.

## New tests

All six new tests live in `test/unit/naming.bats` and pass against the current, unmodified implementation:

- `project_slug strips leading and trailing hyphens produced by normalisation` — `project_slug '/tmp/!!My Project!!'` yields `my-project`, pinning the edge-hyphen stripping step of the shared normalisation for `project_slug` (previously unpinned: no existing test exercised a base whose normalised form has edge hyphens).
- `project_slug returns empty for a base with no alphanumeric characters` — `project_slug '/tmp/!!!'` yields the empty string, pinning the empty-result outcome of the full normalisation chain for `project_slug`.
- `dest_slug collapses runs of non-alphanumeric characters into one hyphen` — `dest_slug '/a  b//c'` yields `a-b-c`, pinning run-collapsing for `dest_slug` (previously pinned only for `project_slug`).
- `dest_slug strips leading and trailing hyphens produced by normalisation` — `dest_slug '/tmp/!'` yields `tmp` and `dest_slug '!project!'` yields `project`, pinning edge-hyphen stripping for `dest_slug` including the case where slash-stripping leaves punctuation at the path edges.
- `dest_slug returns empty when normalisation erases every character` — `dest_slug '/!'` yields the empty string, pinning an empty result produced by the normalisation body itself (all characters non-alphanumeric) as distinct from the already-pinned `dest_slug '/'` empty result produced purely by slash stripping.
- `dest_slug normalises identically to project_slug for the same string` — `dest_slug 'My  Project_v2!'` equals `project_slug '/tmp/My  Project_v2!'` and both equal `my-project-v2`, pinning byte-identical normalisation across the two functions modulo `dest_slug`'s wrapper slash-stripping, which is the duplication property the plan's `slugify` extraction consolidates.

Unit tests for the `slugify` helper itself were not added: the helper does not exist in the current implementation, the invariant forbids editing core files, and the plan only permits ("may be added") adding them alongside the refactor.

## Tests edited

None. The plan requires the existing behaviour-pinning tests in [test/unit/naming.bats](../../../test/unit/naming.bats) to "keep passing unchanged" — every one of them passes against the current implementation and none is superseded, so all are retained verbatim.

## Tests removed

None. The plan states "No existing tests are superseded or removed"; in particular the third copy `project_slug_e2e` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) is explicitly deferred as test-suite duplication out of scope for this resolution, so nothing in the e2e suite is touched.

## Results

`make test-unit` passes 258/258 (was 252 before this pass) and `make test-e2e` passes 76/76; `make lint` and `make format` are clean.
