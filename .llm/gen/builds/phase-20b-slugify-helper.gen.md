# Build: Phase 20b — shared slug normalisation helper in `lib/naming.sh`

Status: SUCCESS

Implements [Phase 20b](../plans/phase-20b-slugify-helper.gen.md): the byte-identical slug normalisation body (lowercase, non-alphanumerics to hyphens, collapse runs, strip edge hyphens) duplicated by `project_slug` and `dest_slug` in [lib/naming.sh](../../../lib/naming.sh) was extracted into a single `slugify` helper called by both, with `dest_slug` keeping its leading/trailing slash stripping as a wrapper detail. All other naming helpers are untouched (per the [naming-dispatch-consolidation deferral](../choices/naming-dispatch-consolidation.gen.md)) and the `project_slug_e2e` copy in the test suite remains out of scope. No verdict or dispute documents were involved; no issue documents were created or resolved.

External-facing output is unchanged: all produced container, volume and image names are byte-identical, confirmed by the unchanged [test/unit/naming.bats](../../../test/unit/naming.bats) pinning suite. `make test-unit` (258/258) and `make test-e2e` (76/76) pass; `shellcheck` and `shfmt -d` are clean. [MAP.gen.md](../../../MAP.gen.md)'s `lib/naming.sh` entry was updated to describe `slugify`. Unit tests for `slugify` itself were not added: the plan marks them optional and test-file creation was not permitted in this session.
