# Review: Container exit hang in `onbox` / `netbox` / `offbox`

## Symptom

Exiting any of the `onbox`, `netbox` or `offbox` containers incurs a
noticeable hang of roughly 5 seconds before control returns to the host.

## Root cause

After the user command/shell (run via `podman exec`) returns, each `run_*`
executor stops the persistent container:

```bash
podman stop -t "$STOP_GRACE_SECONDS" "$ctr"   # STOP_GRACE_SECONDS=5
```

([lib/containers.sh](../../../lib/containers.sh), `run_onbox`/`run_netbox`/
`run_offbox` and the lifecycle executors).

The container's PID 1 is `sleep infinity`:

- The image's `ENTRYPOINT` is
  [image/entrypoint.sh](../../../image/entrypoint.sh).
- `plan_onbox`/`plan_netbox`/`plan_offbox` append `sleep infinity` as the
  container command.
- The entrypoint finishes with `exec bash -c "$*"`. Because bash applies its
  last-command exec optimization to the single-command `-c` string
  `"sleep infinity"`, bash replaces itself with `sleep`, so **PID 1 is
  `sleep`** (confirmed via `/proc/<pid>/cmdline` and `/proc/<pid>/comm`).

`sleep` installs no signal handler. Crucially, **Linux PID 1 ignores
signals whose default action is terminate when no explicit handler is
installed** — so the `SIGTERM` that `podman stop` sends to PID 1 is ignored.
Podman then blocks for the full `STOP_GRACE_SECONDS` (5 s) and only
terminates the container with `SIGKILL` (which cannot be ignored, even by
PID 1).

## Reproduction

Against the real `talkbox/base:latest` image, real entrypoint, `-t 5`:

```
PID 1 cmdline: sleep infinity
PID 1 comm:    sleep
time podman stop -t 5 test-hang2
  warning: "StopSignal SIGTERM failed to stop container ... in 5 seconds, resorting to SIGKILL"
  real    0m5.136s
```

The 5 s is consumed on **every** exit, not just slow ones — the grace
period is never cut short by a clean `SIGTERM` exit.

## Why the prior grace-period change did not help

The closed issue
[podman-stop-aggressive-grace](../issues/podman-stop-aggressive-grace.gen.md)
(and its [choice](../choices/podman-stop-grace-period.gen.md)) raised the
stop timeout from `-t 1` to `-t 5`, on the stated assumption that
"well-behaved processes exit immediately on `SIGTERM`". That assumption is
false for this image: PID 1 is `sleep`, which never honors `SIGTERM`, so
the grace period is **always** fully exhausted. Raising the value from 1 to
5 therefore turned a 1 s hang into a 5 s hang rather than fixing anything.

This is filed as a new issue:
[PID 1 (`sleep infinity`) ignores `SIGTERM`](../issues/pid1-sleep-ignores-sigterm.gen.md).

## Fix directions (not implemented)

The underlying problem is the classic "PID 1 does not handle signals"
mistake. Any fix must give the container a PID 1 that forwards or handles
`SIGTERM`, e.g.:

- Run an init as PID 1: `podman run --init` (uses `catatonit`/`tini`), which
  becomes PID 1, reaps zombies and forwards `SIGTERM` to `sleep` (whose
  default disposition — as a non-PID-1 process — is to terminate). This is
  the smallest change and lives in the planners in
  [lib/containers.sh](../../../lib/containers.sh) (add `--init` to
  `plan_onbox`/`plan_netbox`/`plan_offbox`).
- Or make the entrypoint itself remain PID 1 with an explicit `trap`
  forwarding `SIGTERM` to its child, instead of `exec`-ing `sleep`.

Either approach would let `podman stop` terminate the container promptly on
`SIGTERM`, after which `STOP_GRACE_SECONDS` becomes a true safety upper
bound rather than the always-paid wait.

## Related

- [Issue: PID 1 (`sleep infinity`) ignores `SIGTERM`](../issues/pid1-sleep-ignores-sigterm.gen.md)
- [Issue: `podman stop -t 1` uses an aggressive stop grace period](../issues/podman-stop-aggressive-grace.gen.md) (closed, superseded)
- [Choice: `podman stop` grace period](../choices/podman-stop-grace-period.gen.md)
