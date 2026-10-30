# Phase 28b: serialize the create/recreate/rm paths with a per-container lock

#flow/redgreen #model/default

## Aspects of the specification and issues

Implements the resolution of the issue [concurrent-create-rollback-race](../../issues/concurrent-create-rollback-race.gen.md). No `SPEC.md` behaviour changes; the plan serializes the mutating container lifecycle paths so that simultaneous invocations cannot destroy each other's containers or volumes. `run_recreate`, `--rm-container` and `--rm-image` semantics are unchanged externally.

## External-facing functionality

- Two or more simultaneous first invocations of the same container command (e.g. `onbox` in two terminals on a fresh container): exactly one creates the container; the loser of the race waits for the lock and then sees the winner's container as existing and attaches to it. No `cannot create container` rollback firing on another invocation's container.
- `--recontain`/`--rebuild` and `--rm-container`/`--rm-image` are mutually exclusive with a concurrent create or attach session of the same container, and with each other, for the duration of their plan execution.
- `fetch`/`merge`/`sync` are unaffected (they create only transient no-network containers).

## Key internal design (per the selected choice [concurrent-create-serialization](../../choices/concurrent-create-serialization.gen.md))

- An exclusive `flock` on a per-user, per-container lock file (keyed by the container name, e.g. `<project-slug>.<container>`, under a per-user lock directory such as `${XDG_RUNTIME_DIR}/talkbox/locks` with a per-uid temp fallback; root overridable for tests) covers each mutating critical section:
  - `run_container`: from the `container_exists` check through `create_sandbox` and `podman start` (not the setup/nft/exec tail, so concurrent attach sessions proceed in parallel).
  - `run_recreate`: the whole `plan_recreate` execution including the `podman rm -f --volumes` and its `rollback_creation_and_die` failure path.
  - `run_rm_container` and `run_rm_image`: the whole plan execution.
- `rollback_creation_and_die` is unchanged: under the lock its `podman rm -f`/`podman volume rm -f` can only target resources this invocation's plan created (the `container_exists` check is inside the lock), so the create-vs-create rollback destruction cannot occur; the `run_recreate` caller's intentional removal is unaffected.
- The lock file is released on process death (kernel `flock` semantics), so a killed invocation cannot leave a stale lock.
- The lock helper lives in a small new module (e.g. `lib/locking.sh`) — an acquire-and-release around a critical section (fd-based `flock` with the lock held across the section), sourced by `lib/containers.sh`.

## Files to be created or modified

- `lib/locking.sh` — the per-container exclusive-lock helper (lock path derivation, acquire/release).
- `lib/containers.sh` — wrap the `run_container` create branch, `run_recreate`, `run_rm_container` and `run_rm_image` in the lock.
- `test/unit/containers.bats` / `test/unit/lifecycle.bats` — unit tests for the lock helper and the serialized paths (the podman shim is oblivious to flock; the tests exercise the lock helper directly and that the mutating cores acquire it).
- `test/e2e/lifecycle.bats` — concurrent first-invocations test.
- `MAP.gen.md` — entries for `lib/locking.sh` and the serialized lifecycle.

## Relevant files to read during implementation

- `lib/containers.sh` (`run_container`, `create_sandbox`, `execute_plan`, `rollback_creation_and_die`, `run_recreate`, `run_rm_container`, `run_rm_image`)
- `.llm/gen/issues/concurrent-create-rollback-race.gen.md` and the "First-invocation race" section of `.llm/gen/reviews/multi-terminal-container-sessions.gen.md`
- `test/unit/helpers.bash` (shim), `test/e2e/helpers.bash`, `test/runner.mk` (`systemd-run`/`RuntimeMaxSec` conventions)
- `test/e2e/lifecycle.bats` and `test/unit/lifecycle.bats`

## Tests

- Unit tests: the lock helper acquires exclusively and blocks a second acquirer until release; lock files land under the configured per-user directory and are named per container; `run_container`'s create branch holds the lock across the exists-check/create/start while the exec tail is unlocked (assertable via the lock file's presence during a shim-stalled create); the rollback path under a plan failure removes only this invocation's resources.
- E2e tests: two simultaneous first invocations (`onbox -c --noninteractive 'true'` launched concurrently on a fresh project) both succeed and the container exists and is usable afterwards; a concurrent `--rm-container` does not interleave with a create in a way that removes the freshly created container.
