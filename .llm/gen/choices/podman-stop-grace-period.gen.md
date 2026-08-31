# Choice: `podman stop` grace period

## Context

Every run/lifecycle executor in [lib/containers.sh](../../../lib/containers.sh) stops the container with `podman stop -t 1`, which sends `SIGTERM` and waits only one second before `SIGKILL`. The same literal value `-t 1` is duplicated across nine call sites (`run_onbox`, `run_recontain`, `run_rebuild`, `run_netbox`, `run_offbox`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild`) with no named constant. See the filed [issue](../issues/podman-stop-aggressive-grace.gen.md).

The review notes this is a deliberate trade-off (fast container recycling) but that a larger grace period would be safer, giving processes time to flush and shut down cleanly. The container's foreground process is typically `sleep infinity` (for the persistent containers) or a user shell/command; `podman stop` sends `SIGTERM` to PID 1, and the kernel's default `SIGTERM` handling plus any shell trap or process-group teardown may need more than one second.

## Options

### Option A — Increase to a named constant of 5 seconds (Recommended)

Introduce a single named constant (e.g. `STOP_GRACE_SECONDS=5`) near the top of [lib/containers.sh](../../../lib/containers.sh) and reference it from all nine `podman stop` call sites, replacing the literal `-t 1`.

**Pros:**
- Gives processes a comfortable window to flush and exit (5 seconds), at a negligible cost to the interactive experience (the container is stopping anyway).
- A named constant makes the value tunable and documented in one place; future adjustments touch a single line.
- Matches the review's recommended value.

**Cons:**
- Adds up to ~4 seconds of worst-case latency per container stop compared to `-t 1` (only when a process ignores `SIGTERM` for the full grace period; well-behaved processes exit immediately on `SIGTERM`).

### Option B — Increase to a named constant of 10 seconds

Same as Option A but with a 10-second grace period.

**Pros:**
- Maximally safe for slow-shutting-down processes (e.g. a language server or build daemon with a large buffer flush).

**Cons:**
- Up to ~9 seconds of worst-case stop latency; more than is typically warranted for an interactive development tool.

### Option C — Keep `-t 1` but extract a named constant

Extract the literal into a named constant set to `1`, making it tunable, but do not change the value.

**Pros:**
- No behaviour change; purely makes the value tunable.

**Cons:**
- Does not address the underlying concern that 1 second is aggressive; only defers the decision.

## Recommendation

**Option A (5 seconds, named constant).** Five seconds is a comfortable middle ground: long enough for processes to flush and exit cleanly, short enough that the stop is still effectively immediate for interactive use. Extracting a named constant removes the duplication and makes future tuning trivial.

## Selected option

**Option A (5 seconds, named constant).** Selected by the user. Introduce a named constant `STOP_GRACE_SECONDS=5` in [lib/containers.sh](../../../lib/containers.sh) and reference it from all nine `podman stop` call sites, replacing the literal `-t 1`.

## Related

- [Issue: `podman stop -t 1` uses an aggressive stop grace period](../issues/podman-stop-aggressive-grace.gen.md)
- [Review: repository review](../reviews/repository-review.gen.md) (observation: `run_onbox` / `run_netbox` / `run_offbox` stop with `-t 1`)
