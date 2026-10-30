# Issue: Exiting one of several concurrent sessions stops the container and kills the others

## Affected files

- [lib/containers.sh](lib/containers.sh) — `exec_in_container` (the unconditional `stop_container "$ctr"` after the exec session exits), reached from `run_container` for `onbox`, `netbox` and `offbox`

## Description

`exec_in_container` calls `stop_container "$ctr"` unconditionally after its own exec session finishes. When the same container has multiple concurrent exec sessions (e.g. the same `onbox` opened in two terminals, or an interactive shell plus a brief `onbox -c 'ls'` in another terminal), whichever session exits first stops the whole container, SIGTERM/SIGKILL-ing every other live session after the 5-second grace period (`STOP_GRACE_SECONDS`). Verified empirically: an exec session mid-command exits with status 255 when the container is stopped from a second short-lived exec. A git operation mid-write in another session can additionally leave a stale `index.lock`.

This makes concurrent multi-terminal use of the same `onbox`/`netbox`/`offbox` container unusable in practice, even though the attach itself works (`podman start` is a no-op on a running container and the nft ruleset re-application is idempotent).

## Suggested fix

In `run_container`, capture `container_running "$ctr"` before `podman start`, pass it through to `exec_in_container`, and only call `stop_container` when this invocation started the container from a stopped state. Sessions attaching to an already-running container then leave it running when they exit.

## Related

- [Review: multiple terminals attached to the same container](../reviews/multi-terminal-container-sessions.gen.md)
