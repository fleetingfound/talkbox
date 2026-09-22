# Phase 16b: Eliminate e2e shared-image inter-test coupling via a reusable `ensure_base_image_e2e` helper

Status: `SUCCESS`

This build implements [phase-16b-e2e-shared-image-coupling-helper.gen.md](../plans/phase-16b-e2e-shared-image-coupling-helper.gen.md): the e2e suite now makes the `talkbox/base:latest` image-existence precondition explicit per test via a new `ensure_base_image_e2e` helper called from the `setup()` of every podman-touching `.bats` file, so no test's correctness depends on another test having run. This eliminates the inter-test coupling identified in the review [test-suite-order-image-container-deps.gen.md](../reviews/test-suite-order-image-container-deps.gen.md) — the `deny-allow.bats` rebuild of the shared image (seeding buildah external working containers) and the `netbox-offbox.bats --rm-image` destruction of it. The SPEC's `--rm-image` safety contract ([SPEC.md](SPEC.md) line 253) and `ensure_base_image`'s auto-rebuild-on-absent behaviour in `lib/containers.sh` are unchanged; no production code was modified.

## Overview

- `test/e2e/helpers.bash` - new `ensure_base_image_e2e <talkbox-dir>` helper which, via `sdrun`, checks `podman image exists talkbox/base:latest`, builds it with `podman build -t talkbox/base:latest -f "$talkbox-dir/image/Containerfile" "$talkbox-dir/image"` when absent, and best-effort force-removes buildah external working containers referencing `talkbox/base:latest` (mirroring `prune_external_image_containers` in `lib/containers.sh`) so buildah artifacts do not accumulate across the suite.
- `test/e2e/{deny-allow,git-identity,git-transport,lifecycle,merge-sync,netbox-offbox,onbox}.bats` - each `setup()` gains a call to `ensure_base_image_e2e "$TALKBOX"` after `TALKBOX` is assigned.
- `test/e2e/deny-allow.bats` - the inline `podman image exists` + `podman build` preamble of the "onbox --deny-ip blocks a deny-listed connection attempted during setup" test is replaced by a single `ensure_base_image_e2e "$TALKBOX"` call; the test's direct `podman run talkbox/base:latest` is preserved.
- `test/e2e/smoke.bats` is untouched: it does not touch podman and is excluded by the plan.

## Test edits

Every edited test file was changed solely to implement the plan's key interfaces; no test's assertions or expectations were altered:

- Plan (L41): "Each of the 7 e2e `.bats` files that touch podman (`deny-allow`, `git-identity`, `git-transport`, `lifecycle`, `merge-sync`, `netbox-offbox`, `onbox`) gains a call to `ensure_base_image_e2e "$TALKBOX"` in its `setup()`, after `TALKBOX` is assigned. `smoke.bats` is excluded (it does not touch podman)." — applied verbatim.
- Plan (L43): "`test/e2e/deny-allow.bats` lines 167-169: the inline `if ! sdrun podman image exists … podman build …` preamble is replaced by a single `ensure_base_image_e2e "$TALKBOX"` call. The direct `podman run talkbox/base:latest` at line 188 is preserved" — applied verbatim.
- Plan (L36-39): the helper implements the stated interface — checks existence via `sdrun`, builds from `<talkbox-dir>/image/Containerfile` with context `<talkbox-dir>/image`, and prunes external working containers referencing `talkbox/base:latest` mirroring `prune_external_image_containers`.

## Verification

- `make test-unit` - exit `0`; 267/267 tests passed.
- `make test-e2e` - exit `0`; 76/76 tests passed, including the regression targets `netbox --rm-image removes the base image` and the `deny-allow.bats` setup-phase deny test. (One first-run timeout of `git-transport.bats :: onbox fetch --all …` was environmental load flakiness: the test passed in isolation and in the full re-run, and the change adds only a fast idempotent setup check.)
- ShellCheck (`make lint`) and `shfmt` (`make format`) are clean.
