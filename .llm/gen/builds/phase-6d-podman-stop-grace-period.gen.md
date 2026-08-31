# Phase 6d: Increase `podman stop` grace period to 5 seconds

Status: `SUCCESS`

This build implements [phase-6d-podman-stop-grace-period.gen.md](../plans/phase-6d-podman-stop-grace-period.gen.md), which resolves the issue [podman-stop-aggressive-grace.gen.md](../issues/podman-stop-aggressive-grace.gen.md) per the selected design in [podman-stop-grace-period.gen.md](../choices/podman-stop-grace-period.gen.md) (Option A — 5 seconds, named constant): the stop grace period is an implementation detail, so no aspect of `SPEC.md` / `SPEC.gen.md` is altered.

## Overview

- `lib/containers.sh` - added the scalar constant `STOP_GRACE_SECONDS=5` after the `source` lines and before the first function (not exported), and replaced the literal `-t 1` with `-t "$STOP_GRACE_SECONDS"` at all nine `podman stop` call sites across `run_onbox`, `run_recontain`, `run_rebuild`, `run_netbox`, `run_offbox`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild`.

## Test edits

None. As the plan states, the grace-period value is not meaningfully observable in a unit test (the executors call `podman` directly) and the e2e suite exercises real containers that stop well within 5 seconds, so no tests were added or modified.

## Verification

- `make test-unit` - exit `0`; 162/162 tests passed.
- `make test-e2e` - exit `0`; 57/57 tests passed unchanged, confirming no stop-related timeout regressions.
- `shellcheck -x lib/containers.sh` clean; `shfmt` reports no formatting changes on the edited script.
