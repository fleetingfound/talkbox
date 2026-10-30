# Choice: Concurrent session stop mechanism (stop only when no sessions remain)

> Selected option replaces the originally drafted options below: the user chose a count of the container's live `podman exec` sessions (`podman exec list`) taken after the exiting session's own exec terminates. See "selected option".

## context

`exec_in_container` calls `stop_container` unconditionally after its exec session exits, so the first terminal to leave a multi-terminal session set kills every other live session (see the issue [concurrent-session-exit-stops-container](../issues/concurrent-session-exit-stops-container.gen.md)).

The requirement is that a container is stopped only when **no other talkbox session is attached to it**, regardless of the order in which sessions start and exit and of how many sessions are open. The minimal fix suggested in the issue (record `container_running` before `podman start` and stop only if this invocation started the container from a stopped state) does not satisfy this: if the session that started the container exits first (with others still attached), the container is stopped while the other sessions are still live.

## options

### Option A: Per-container session registry with per-PID files (Recommended)

Keep a per-user, per-container session directory (under a runtime dir such as the user's `XDG_RUNTIME_DIR`, with a temp-dir fallback), holding one empty per-session file named by the session's PID. Each `run_container` invocation registers a session file before it starts or attaches to the container and unregisters after its exec session exits. On session exit it removes its own file, prunes entries whose PIDs are no longer alive (sessions killed without cleanup), counts the remaining live session files for the container, and calls `stop_container` only when the count reaches zero.

- **Pros:** Correct for every ordering and count of sessions; the last session to exit stops the container no matter which one started it; crash-tolerant — a killed session leaves a dead-PID entry that the next exit prunes; no reliance on when the container was started.
- **Cons:** Introduces a small session-registry module and a per-exit directory scan; a SIGKILLed session's container stays running until the next session exits or it is stopped manually (mitigated by dead-PID pruning at every exit).

### Option B: Started-from-stopped ownership flag

Record `container_running` before `podman start`; stop on exit only when this invocation started the container from a stopped state.

- **Pros:** Minimal change (a boolean threaded into `exec_in_container`).
- **Cons:** Fails the ordering requirement — the starter's exit stops the container while other sessions are still attached (starter exits first, attacher's terminal remains).

### Option C: Starter-ownership flag plus session count

Like A, but only the session that started the container from a stopped state is permitted to stop it, and only when the session count is zero.

- **Pros:** Preserves "the starter owns the container lifecycle" semantics for containers started by talkbox; containers started externally (e.g. by `podman start` by hand) are never stopped by a talkbox session exit.
- **Cons:** More state (flag plus count); leaves the container running indefinitely when the starter is killed or exits early while attacher sessions remain live after the last one exits.

## recommendation

**Option A.** It is the only option that satisfies "stop only when no other sessions exist" under every start/exit ordering, and dead-PID pruning keeps it robust against sessions that die without cleanup. The externally-started container stopped by the last exiting session is consistent with "no talkbox sessions remain" semantics.

## selected option

**A session count derived from podman's own exec-session listing** (user-specified variant of Option A). Instead of a talkbox-side per-PID session registry, `exec_in_container` queries the container's live exec sessions (`podman exec list <container>`) after its own exec session terminates: if no exec sessions remain in the container, it stops the container; otherwise it leaves it running. The count is inherently per-container, needs no registry state, and captures sessions regardless of how they were opened (interactive shell, `-c` command, `񐐐`sync` exec). Any session in the container defers the stop — including the setup.sh exec of a concurrent session and the exec of `run_sync_in_container`, which is the desired behaviour. Small window: a session that starts its exec in the gap between the exiting session's listing and its stop lands on a stopping container; this window is milliseconds and inherent to any list-then-stop scheme.
