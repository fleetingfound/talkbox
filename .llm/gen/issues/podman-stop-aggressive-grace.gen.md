# Issue: `podman stop -t 1` uses an aggressive stop grace period

## Affected files

- [lib/containers.sh](../../../lib/containers.sh) — `run_onbox`, `run_recontain`, `run_rebuild`, `run_netbox`, `run_offbox`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild` (nine call sites)

## Description

Every run/lifecycle executor in [lib/containers.sh](../../../lib/containers.sh) stops the container with `podman stop -t 1`, which sends `SIGTERM` and waits only one second before sending `SIGKILL`. A process mid-write (a coding agent flushing output, an editor saving a file, a build tool writing artefacts) could lose unflushed data within that one-second window.

This is a deliberate trade-off for fast container recycling, and is unlikely to cause issues in practice for typical interactive/coding-agent use. However, a larger grace period (e.g. 5 seconds) would give processes time to flush and shut down cleanly, at a negligible cost to the interactive experience.

The same `-t 1` value is duplicated across nine call sites with no named constant, so any future adjustment requires touching all of them.

## Suggested fix

Increase the stop grace period to a safer value and introduce a single named constant for it so the value is tunable and documented in one place. See the associated choice document for the design options.

## Related

- [Review: repository review](../reviews/repository-review.gen.md) (observation: `run_onbox` / `run_netbox` / `run_offbox` stop with `-t 1`)
- [Choice: podman stop grace period](../choices/podman-stop-grace-period.gen.md)
