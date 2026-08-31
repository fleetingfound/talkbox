# Phase 7: GPU support (`--gpu` flag)

Status: `SUCCESS`

This build implements [phase-7-gpu-support.gen.md](../plans/phase-7-gpu-support.gen.md), which implements the **gpu support** section of [SPEC.md](../../../SPEC.md) (lines 347-355): when `--gpu` is passed to `onbox`, `netbox` or `offbox`, the created container is given the extra `podman` options `--device nvidia.com/gpu=all` and `--group-add keep-groups`. The flag threading follows the selected design in [gpu-flag-threading.gen.md](../choices/gpu-flag-threading.gen.md) (Option B — read the `TALKBOX_GPU` global directly inside the three planners).

## Overview

- `lib/options.sh` - `parse_talkbox_options` now sets `TALKBOX_GPU="no"` by default and recognises the `--gpu` flag, setting `TALKBOX_GPU="yes"`.
- `lib/containers.sh` - `plan_onbox`, `plan_netbox` and `plan_offbox` append `--device nvidia.com/gpu=all` and `--group-add keep-groups` alongside the other top-level `podman create` flags (after the `--cap-drop` options, before the `-v` mount list) when `TALKBOX_GPU == yes`. Because the three planners are the single source of truth for create arguments, the default-create, recontain and rebuild paths all inherit GPU support with no further changes.
- `talkbox.sh` - unchanged; the global is consumed by the planners, not the dispatchers.

## Test edits

None made by this build; the red-green tests for the phase were committed by the preceding `@puzzler` step (commit `04861e8`) and are described in [phase-7-gpu-support.gen.md](../tests/phase-7-gpu-support.gen.md). The e2e tests use a `podman` shim (see the test document's deviation note) so they pass deterministically on a GPU-less host.

## Verification

- `make test-unit` - exit `0`; 170/170 tests passed (including the three new `options.bats` parser tests, the three `containers.bats` planner tests and the two `netbox-offbox.bats` planner tests).
- `make test-e2e` - exit `0`; 60/60 tests passed (including the three new `--gpu` e2e tests), confirming no regressions in the non-`--gpu` paths.
- `shellcheck lib/options.sh lib/containers.sh` - no errors (only pre-existing `SC1091` info notes on `source` lines); `shfmt` reports no formatting changes.
