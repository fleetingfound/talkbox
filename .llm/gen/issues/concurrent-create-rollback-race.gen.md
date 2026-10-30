# Issue: Simultaneous first invocations race on create and the loser's rollback destroys the winner's container

## Affected files

- [lib/containers.sh](lib/containers.sh) — `run_container` (the `container_exists` check followed by `create_sandbox`) and `rollback_creation_and_die`

## Description

When two terminals invoke the same container command (e.g. `onbox` in both) while the container does not yet exist, both invocations pass the `container_exists` check and both proceed to `create_sandbox`. Both run `podman create` with the same container name; one fails, and its `execute_plan` failure path calls `rollback_creation_and_die`, which runs `podman rm -f` on the shared container name and `podman volume rm -f` on the shared volume names. By then those names may refer to the *other* invocation's successfully created container and volumes (including the `<project-slug>.<container>.gitdir` volume holding the container's git history), so the loser's rollback can destroy the winner's container — potentially while the winner's exec session is live, killing it — and delete its freshly created volumes.

The window is narrow, but the failure mode is destructive and gives both terminals confusing errors.

## Suggested fix

Make the rollback verify ownership before deleting: only remove the container/volumes if this invocation actually created them (e.g. re-check that the create step itself failed rather than a later step, capture the created container ID from the winning create, or take an exclusive per-container lock around the create path). Note that `rollback_creation_and_die` is also used by `run_recreate`, where removing the named container is intentional (the old container was already removed by the plan), so the guard must distinguish the two callers.

## Related

- [Review: multiple terminals attached to the same container](../reviews/multi-terminal-container-sessions.gen.md)
- [Issue: concurrent session exit stops the container and kills the others](concurrent-session-exit-stops-container.gen.md)
