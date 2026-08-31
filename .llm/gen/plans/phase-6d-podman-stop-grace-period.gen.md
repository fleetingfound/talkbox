# Plan: Phase 6d — Increase `podman stop` grace period to 5 seconds

#flow/unified #model/default

## Specification scope

No aspect of `SPEC.md` / `SPEC.gen.md` is altered. This resolves the open issue [`podman stop -t 1` uses an aggressive stop grace period](../issues/podman-stop-aggressive-grace.gen.md), per the selected design in [`podman stop` grace period](../choices/podman-stop-grace-period.gen.md) (Option A — 5 seconds, named constant). The stop grace period is an implementation detail not prescribed by the specification.

## To be implemented

- Introduce a single named constant (e.g. `STOP_GRACE_SECONDS=5`) near the top of [lib/containers.sh](../../../lib/containers.sh) (after the `source` lines, before the first function), replacing the literal `1` that is currently duplicated across nine `podman stop -t 1` call sites.
- Replace every `podman stop -t 1` occurrence with `podman stop -t "$STOP_GRACE_SECONDS"` in the nine executors: `run_onbox`, `run_recontain`, `run_rebuild`, `run_netbox`, `run_offbox`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild`.
- The constant must be a simple scalar assignment (not exported — it is only needed within the shell process running the executors).

## To be deferred

- Nothing.

## External-facing functionality

Containers now receive a 5-second `SIGTERM`-to-`SIGKILL` grace period when stopped (up from 1 second). This is a safety improvement: processes mid-write have time to flush and exit. The user-observable effect is that a container hosting a process that ignores `SIGTERM` may take up to ~5 seconds to stop instead of ~1; well-behaved processes still stop immediately on `SIGTERM`.

## Files to be created

- None.

## Files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — all nine `podman stop -t 1` call sites.

## Key internal interfaces

- `STOP_GRACE_SECONDS` — a new scalar constant in [lib/containers.sh](../../../lib/containers.sh) holding the stop grace period in seconds, referenced by every `podman stop` call site.

## Tests

The grace-period value is not meaningfully observable in a unit test (the executors call `podman` directly, which is not mocked in unit tests) and the e2e suite exercises real containers that stop well within 5 seconds. There is no failing-test-first cycle to write, so the whole phase is implemented by a single agent.

- **Unit tests:** none required. The existing unit tests do not exercise `podman stop` and are unaffected.
- **End-to-end tests:** no e2e test changes. The full e2e suite must continue to pass — containers stop and are removed across all run/lifecycle e2e cases. Run the full e2e suite to confirm no stop-related timeout regressions.
