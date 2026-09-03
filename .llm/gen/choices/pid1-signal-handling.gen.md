# Choice: PID 1 signal handling for persistent containers

## Context

Every `onbox`/`netbox`/`offbox` persistent container runs `sleep infinity` as
its final command. The entrypoint
([image/entrypoint.sh](../../../image/entrypoint.sh)) ends with
`exec bash -c "$*"`, and bash's last-command exec optimization replaces bash
with `sleep`, so **PID 1 is `sleep`**. `sleep` installs no signal handler,
and Linux does not apply the default terminate action to PID 1 for unhandled
signals — so the `SIGTERM` sent by `podman stop` is ignored. Podman then
blocks for the full `STOP_GRACE_SECONDS` (5 s) on every exit and only then
resorts to `SIGKILL`. See the [issue](../issues/pid1-sleep-ignores-sigterm.gen.md)
and the [review](../reviews/container-exit-hang.gen.md).

The fix must give the container a PID 1 that either forwards or handles
`SIGTERM`, so that `podman stop` terminates the container promptly and
`STOP_GRACE_SECONDS` becomes a true safety upper bound rather than an
always-paid wait.

The persistent containers are created by `plan_onbox`, `plan_netbox` and
`plan_offbox` in [lib/containers.sh](../../../lib/containers.sh) (which are
also reused by the `plan_*_recontain`/`plan_*_rebuild` planners). The
one-shot `podman run --rm` containers (`plan_volume_populate`,
`container_sync_cmd` non-running path) run a command that exits on its own
and are never `podman stop`'d, so they are unaffected by this issue.

## Options

### Option A — `podman --init` on the three persistent planners (Recommended)

Add the `--init` flag to the argument lists built by `plan_onbox`,
`plan_netbox` and `plan_offbox` in [lib/containers.sh](../../../lib/containers.sh).
Podman's `--init` injects a minimal init (`catatonit`/`tini`) as PID 1, which
reaps zombies and forwards `SIGTERM` to its child. `sleep` then runs as a
non-PID-1 process whose default `SIGTERM` disposition is to terminate, so
`podman stop` returns promptly.

**Pros:**
- Smallest, most localized change — three lines in the planners, no image or
  entrypoint changes.
- A runtime flag, so it applies to every persistent container regardless of
  which image (base, netbox-root, offbox-root) is used.
- Brings proper zombie reaping as a side benefit.
- Does not touch [image/entrypoint.sh](../../../image/entrypoint.sh), which is
  already complex and runs for one-shot containers too.
- `podman exec` is unaffected — exec'd commands run in the container
  namespaces, not as children of PID 1.

**Cons:**
- Depends on an init binary being available to podman (`catatonit` is bundled
  with podman on most distros, but not universally guaranteed). If unavailable,
  `podman create --init` fails at create time, which would surface
  immediately rather than silently.

### Option B — Entrypoint `trap`-based signal forwarding

Modify [image/entrypoint.sh](../../../image/entrypoint.sh) so that, instead of
`exec bash -c "$*"`, it remains PID 1, installs a `SIGTERM` trap, runs the
command as a child, and forwards `SIGTERM` to the child on receipt. This
requires an image rebuild.

**Pros:**
- Self-contained in the image; no dependency on an external init binary.
- Works regardless of how the container is launched.

**Cons:**
- More invasive: touches the entrypoint, which is already complex and also
  runs for one-shot `podman run --rm` containers where the hang does not
  occur (the command exits on its own); the trap logic must behave correctly
  in both paths.
- Requires an image rebuild and a bump of the base image; existing committed
  netbox/offbox root images would need regeneration.
- bash-as-PID-1 does not reap zombies unless `SIGCHLD` is also trapped,
  adding further complexity.
- Larger blast radius for a problem that has a one-line runtime fix.

### Option C — Change the container command to a signal-handling loop

Replace `sleep infinity` (appended by the three planners) with a small
shell command that traps `SIGTERM` and exits, e.g.
`bash -c 'trap "exit 0" TERM; while true; do sleep 1; done'`. Because the
entrypoint execs this, bash becomes PID 1 with a trap installed, so `SIGTERM`
is caught and the container exits.

**Pros:**
- Localized to the planners (no image/entrypoint change).
- No external init-binary dependency.

**Cons:**
- Hacky: a hand-rolled mini-init embedded as a command string; harder to read
  and reason about than `--init`.
- bash-as-PID-1 still does not reap zombies.
- The `while/sleep 1` loop adds a tiny wakeup latency (up to ~1 s) on stop,
  versus the immediate termination that `--init` gives.
- Duplicates responsibility that `--init` already provides correctly.

## Recommendation

**Option A (`--init` on the three persistent planners).** It is the smallest,
cleanest fix, localized to [lib/containers.sh](../../../lib/containers.sh),
requires no image rebuild, and brings zombie reaping as a bonus. The only
risk is init-binary availability, which surfaces immediately at `podman
create` time if absent and can be confirmed by the existing base-image
availability check.

With `--init` in place, `STOP_GRACE_SECONDS=5` becomes a true safety upper
bound (consumed only in pathological cases) rather than an always-paid wait;
no change to the grace-period value is required.

## Selected option

**Option A (`--init` on the three persistent planners), using `catatonit`.**
Selected by the user. Add the `--init` flag to the argument lists built by
`plan_onbox`, `plan_netbox` and `plan_offbox` in
[lib/containers.sh](../../../lib/containers.sh). Podman will inject
`catatonit` as PID 1, which reaps zombies and forwards `SIGTERM` to `sleep`
(whose default disposition as a non-PID-1 process is to terminate), so
`podman stop` returns promptly and `STOP_GRACE_SECONDS=5` becomes a true
safety upper bound rather than an always-paid wait. No image or entrypoint
changes are required.

## Related

- [Issue: PID 1 (`sleep infinity`) ignores `SIGTERM`](../issues/pid1-sleep-ignores-sigterm.gen.md)
- [Review: Container exit hang](../reviews/container-exit-hang.gen.md)
- [Choice: `podman stop` grace period](podman-stop-grace-period.gen.md)
