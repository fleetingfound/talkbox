# Build: Podman-backed gitdir history probe in `require_git_history`

Status: `BLOCKED`

Implements [the plan](../plans/gitdir-history-podman-probe.gen.md), which resolves [the gitdir host-path-check issue](../issues/onbox-merge-gitdir-volume-host-path-check.gen.md) by replacing `require_git_history`'s host-side `podman volume inspect` mountpoint stat with a no-network `podman run` HEAD probe and interpreting the probe outcome three ways; the blocked status is due solely to [the dispute over the unit `podman()` mock swallowing the probe's not-found exit](../disputes/gitdir-history-probe-not-found-exit-swallowed.gen.md), not to the implementation.

## Changes

- [lib/git.sh](../../../lib/git.sh):
  - New planner `gitdir_probe_cmd <out> <project> <container>` alongside `gitdir_bundle_cmd`, in the same nameref style: `plan_no_net_run` prefix (`podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000`), the read-only gitdir-volume mount `<project-slug>.<container>.gitdir:/gitdir:ro`, the base image (`base_image_name`), and the probe command `test -e /gitdir/HEAD` (11 tokens).
  - `require_git_history` rewritten: unchanged `git_tracked` and `require_gitdir_volume` guards, then it assembles and executes the probe with stderr captured (`2>&1 >/dev/null`) and maps the exit status — 0 → history present; 1 → the unchanged `no git history in the <container> gitdir volume; start the container first` message; any other status → a distinct `talkbox:` diagnostic naming the container and gitdir volume and surfacing the captured podman stderr. The host-side `podman volume inspect` call is gone; no other `volume inspect` usage remains in `lib/`.
- [MAP.gen.md](../../../MAP.gen.md): the `lib/git.sh` entry now describes the podman-run HEAD probe instead of the mountpoint stat.
- No changes to `run_fetch`, `gitdir_volume_exists`, `run_sync`/`run_merge` control flow, bundle fetch, sync-in-container or `custom_merge` behaviour, per the plan's deferred aspects.

## Verification

- `make lint` and `make format` pass.
- `make test-unit`: 308/309 — the only failure is `run_merge dies with the start the container first message when the gitdir volume has no HEAD`, traced (with a verbatim out-of-band replica of the fixture) to the disputed helper: `mock_container_run` correctly returns 1 for an absent HEAD, but the `podman()` wrapper's trailing `return 0` discards it, so no conforming implementation can observe the not-found outcome in the unit suite.
- `make test-e2e`: 81/81, including the real-podman probe pass path (all merge/sync e2e tests) and the real-podman not-found path (`onbox merge on an uninitialised gitdir volume errors with a talkbox message`).

## Linked documents

- Plan: [gitdir-history-podman-probe.gen.md](../plans/gitdir-history-podman-probe.gen.md) — replaces the host-side mountpoint stat with the podman-run HEAD probe and three-way diagnostics.
- Test suite: [gitdir-history-podman-probe.gen.md](../tests/gitdir-history-podman-probe.gen.md) — the red/green suite pinning the planner structure, the three outcomes and the rewritten fixtures.
- Dispute: [gitdir-history-probe-not-found-exit-swallowed.gen.md](../disputes/gitdir-history-probe-not-found-exit-swallowed.gen.md) — the unit `podman()` mock discards `mock_container_run`'s exit status, making the missing-HEAD `run_merge` unit test unpassable for any conforming implementation.
- Issue resolved: [onbox-merge-gitdir-volume-host-path-check.gen.md](../issues/onbox-merge-gitdir-volume-host-path-check.gen.md) — marked complete; the mountpoint stat it describes no longer exists.
