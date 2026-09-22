# Plan: Phase 16b — Eliminate e2e shared-image inter-test coupling via a reusable `ensure_base_image_e2e` helper

#flow/unified #model/default

## Specification scope

No aspect of `SPEC.md` / `SPEC.gen.md` is implemented or altered. This phase is a test-infrastructure change that eliminates the inter-test coupling identified in the review [test-suite-order-image-container-deps](../reviews/test-suite-order-image-container-deps.gen.md): the single shared `talkbox/base:latest` image that crosses test boundaries in the e2e suite.

The SPEC's `--rm-image` safety contract (SPEC.md line 253) and `ensure_base_image` auto-rebuild-on-absent behaviour (lib/containers.sh) are unchanged. The change makes the image-existence precondition **explicit per-test** via a shared helper, rather than implicit via `talkbox.sh`'s internal auto-rebuild, so that no test's correctness depends on another test having run.

## To be deferred

- Moving the `--rm-image` test to a last-sorting file (`zz-rm-image.bats`). With the helper called in every `setup()`, the `--rm-image` test's destruction of the shared image no longer creates a coupling — subsequent tests explicitly rebuild via the helper. Reordering is therefore unnecessary and is deferred.
- Suite-level `setup_suite`/`teardown_suite` for image lifecycle. The per-test helper makes suite-level machinery redundant for this purpose.
- Deduplication of the three `run_*_rm_image` functions in lib/containers.sh (already deferred by Phase 16a).

## External-facing functionality

None. This phase modifies only test files; no user-facing behaviour changes.

## Files to be created

- None.

## Files to read during implementation

- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — where the new helper is added; existing `mk_talkbox`, `teardown_talkbox`, `sdrun` helpers to follow as patterns.
- [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats) — lines 162-196: the only e2e test with an inline `podman image exists` + `podman build` preamble (to be replaced by the helper).
- [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) — lines 156-165: the `--rm-image` test that destroys the shared image.
- [test/e2e/{git-identity,git-transport,lifecycle,merge-sync,onbox}.bats](../../../test/e2e) — `setup()` functions to extend with the helper call.
- [lib/containers.sh](../../../lib/containers.sh) — `prune_external_image_containers` (lines 216-223) and `ensure_base_image` (lines 172-176) as reference for the build + prune pattern the helper mirrors.
- [image/Containerfile](../../../image/Containerfile) — the Containerfile path the helper builds from.

## Key internal interfaces

- A new helper function in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) (e.g. `ensure_base_image_e2e <talkbox-dir>`) that:
  1. Checks `podman image exists talkbox/base:latest` (via `sdrun`).
  2. If absent, runs `sdrun podman build -t talkbox/base:latest -f "<talkbox-dir>/image/Containerfile" "<talkbox-dir>/image"`.
  3. After any build (or unconditionally, best-effort), prunes external working containers referencing `talkbox/base:latest` — mirroring `prune_external_image_containers` in lib/containers.sh — so buildah artifacts do not accumulate across the suite. This eliminates the `deny-allow.bats` → `netbox-offbox.bats` external-container coupling at its source; Phase 16a's `prune_external_image_containers` at `--rm-image` time remains as defence-in-depth.

- Each of the 7 e2e `.bats` files that touch podman (`deny-allow`, `git-identity`, `git-transport`, `lifecycle`, `merge-sync`, `netbox-offbox`, `onbox`) gains a call to `ensure_base_image_e2e "$TALKBOX"` in its `setup()`, after `TALKBOX` is assigned. `smoke.bats` is excluded (it does not touch podman).

- [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats) lines 167-169: the inline `if ! sdrun podman image exists … podman build …` preamble is replaced by a single `ensure_base_image_e2e "$TALKBOX"` call. The direct `podman run talkbox/base:latest` at line 188 is preserved (the test needs direct access to the base image to test nft deny in isolation).

- No changes to [lib/containers.sh](../../../lib/containers.sh) or any production code.

## Tests

Requires tests:

- **End-to-end tests**: the existing e2e suite is the regression target. After the change, every e2e test must still pass, including the `netbox --rm-image removes the base image` test (which now benefits from subsequent tests explicitly rebuilding via the helper rather than silently relying on `talkbox.sh`'s auto-rebuild). The `--rm-image` test's own assertions are unchanged.
- No new unit tests are required. The helper is a thin test-utility wrapper around `podman image exists` / `podman build` / `podman rm --external`; its correctness is exercised by the e2e suite itself. A unit test with a podman shim could be added but offers little value over the real e2e exercise.
