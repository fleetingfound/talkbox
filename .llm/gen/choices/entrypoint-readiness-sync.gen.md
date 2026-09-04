# Choice: Entrypoint readiness synchronization mechanism

## Context

The `run_onbox`/`run_netbox`/`run_offbox` executors in
[lib/containers.sh](../../../lib/containers.sh) call `podman exec` immediately
after `podman start`, without waiting for [image/entrypoint.sh](../../../image/entrypoint.sh)
to finish its start-up work (dotfiles copy, git identity config writes, and the
gitdir-volume `git init`/`git fetch host`/`git reset --mixed` block). Under load
this causes intermittent failures in git-touching e2e tests. See the
[issue](../issues/e2e-fresh-container-exec-races-entrypoint.gen.md).

The persistent containers use `sleep infinity` as their command, with the image
ENTRYPOINT (`entrypoint.sh`) performing setup and then `exec bash -c "$*"`
replacing itself with `sleep infinity`. `podman start` returns as soon as the
container's PID 1 begins — before the entrypoint setup completes. `podman exec`
then runs against a container whose entrypoint has not yet finished initialising
the git repository, writing git config, or copying dotfiles.

A fix must make the executors wait until the entrypoint has completed its setup
before running the user command via `podman exec`.

## Options

### Option A — Tmpfs sentinel file (Recommended)

Mount a tmpfs at `/run/talkbox` in the three persistent-container planners
(`plan_onbox`, `plan_netbox`, `plan_offbox`). The entrypoint writes a sentinel
file (e.g. `/run/talkbox/ready`) as its final action before `exec`. The
executors, after `podman start`, poll for the sentinel via a single `podman exec`
that loops internally with `sleep`, bounded by a timeout. Once the sentinel
exists, the executor proceeds to the user-command `podman exec`.

Tmpfs is ephemeral: it is empty on every container start (fresh create or
restart of a stopped container), so there is no stale sentinel from a previous
run. When the container is already running (e.g. a second `run_onbox` call
without a stop), the sentinel from the current run exists and the poll returns
immediately.

**Pros:**
- Race-free: tmpfs is cleared on each container start, so no stale sentinel can
  produce a false positive.
- No image rebuild required for the mount (tmpfs is a runtime `--tmpfs` flag);
  the entrypoint change requires a rebuild but is a one-line addition.
- Minimal latency in the common case: the internal poll loop sleeps in small
  increments (e.g. 0.1 s) and exits as soon as the sentinel appears.
- Self-contained: no dependency on podman healthcheck support or external tools.
- The tmpfs mount is an implementation detail invisible to the user.

**Cons:**
- Adds a `--tmpfs` flag to the three planners (a minor increase in plan
  complexity).
- The poll timeout must be chosen conservatively; if the entrypoint hangs, the
  executor waits for the full timeout before erroring.

### Option B — Filesystem sentinel with remove-at-start

The entrypoint removes the sentinel at the very first line of setup, then
creates it at the end. The executors poll for the sentinel. No tmpfs mount is
needed — the sentinel lives in the container's writable layer.

**Pros:**
- No `--tmpfs` flag or mount change; only the entrypoint and executors change.

**Cons:**
- Not race-free: there is a window between `podman start` returning and the
  entrypoint executing `rm -f` where the old sentinel from a previous run still
  exists. The executor's poll could see it and proceed prematurely. Under heavy
  load this window widens.
- The sentinel persists in the container's writable layer across restarts,
  requiring the remove-at-start discipline to be maintained correctly.

### Option C — Podman healthcheck

Configure a `HEALTHCHECK` in the Containerfile (or via `--healthcheck-cmd` at
create time) that tests for entrypoint completion (e.g. `test -f /run/talkbox/ready`).
The executors poll `podman inspect --format '{{.State.Health.Status}}'` until it
reports `healthy`.

**Pros:**
- Uses podman's built-in health infrastructure.
- No custom poll loop in the executors (replaced by inspect polling).

**Cons:**
- Healthchecks run on a polling interval (default 30 s start period), which is
  far too slow for this use case; the start-period and interval would need
  aggressive tuning.
- Adds complexity (healthcheck command, start-period, interval, retries) for a
  simple synchronization need.
- Healthcheck status is not designed for synchronous startup waits; it is
  intended for ongoing liveness monitoring.
- Requires the tmpfs sentinel anyway (or a filesystem sentinel with the same
  stale-sentinel problem as Option B).

### Option D — Move entrypoint setup into an exec step

Instead of the image ENTRYPOINT performing setup, the executor runs
`podman start` (with a trivial command like `sleep infinity` and no ENTRYPOINT
setup), then runs the setup script via `podman exec`, then runs the user
command. The entrypoint script remains available on `PATH` for manual use per
the SPEC, but is not invoked automatically as the container ENTRYPOINT.

**Pros:**
- Eliminates the race entirely: setup is run synchronously by the executor
  before the user command.
- No sentinel or polling needed.

**Cons:**
- Significant architectural change: the entrypoint's automatic-on-start
  behaviour is prescribed by SPEC.md ("Whenever one of these containers starts,
  the script `entrypoint.sh` copies these into `/home/dev/`"). Moving setup to
  an exec step changes this contract.
- The `--recontain`/`--rebuild` lifecycle verbs would also need to run the
  setup exec, or accept that freshly recreated containers are not initialised
  until the next `run_*` call.
- `podman commit` (used by netbox/offbox inheritance) captures the container
  state at commit time; if setup runs via exec after start, the committed image
  may or may not include the setup results depending on timing.
- Larger blast radius for a problem that has a clean, localized fix.

## Recommendation

**Option A (tmpfs sentinel file).** It is race-free, localized to the three
persistent-container planners and the entrypoint, requires no architectural
changes, and adds minimal latency in the common case. The tmpfs mount ensures
no stale sentinel can produce a false positive on container restart, which is
the key advantage over Option B. The entrypoint change is a single line (write
the sentinel before `exec`), and the executor change is a bounded poll loop.

The one-shot `podman run --rm` containers (`plan_volume_populate`,
`container_sync_cmd` non-running path) do not use `podman exec` — the entrypoint
runs the command itself after setup — so they are unaffected and do not need the
tmpfs mount or sentinel.

## Selected option

**Option A (tmpfs sentinel file).** Selected by the user. Mount a tmpfs at
`/run/talkbox` in the three persistent-container planners. The entrypoint writes
a sentinel file (`/run/talkbox/ready`) as its final action before `exec`. The
executors poll for the sentinel via a single `podman exec` that loops internally
with `sleep`, bounded by a timeout. Tmpfs is cleared on each container start,
ensuring no stale sentinel can produce a false positive.

## Related

- [Issue: e2e commands executed on a freshly started container race the entrypoint](../issues/e2e-fresh-container-exec-races-entrypoint.gen.md)
