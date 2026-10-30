# Phase 28a: stop the container only when no exec sessions remain

#flow/redgreen #model/default

## Aspects of the specification and issues

Implements the resolution of the issue [concurrent-session-exit-stops-container](../../issues/concurrent-session-exit-stops-container.gen.md). `SPEC.md` does not address concurrent sessions; this plan refines the implementation-defined exec-then-stop tail of `run_container` so that a container is stopped only when no exec sessions remain in it, regardless of the order in which sessions start and exit, or how many are open.

Deferred: the other concurrency hazards documented in the review [multi-terminal-container-sessions](../../reviews/multi-terminal-container-sessions.gen.md) — `setup.sh` re-invocation side effects (dotfile clobbering, module re-copy) and duplicate nft rules from repeated installs — are out of scope, as is the create/rollback race handled separately by the create-serialization plan.

## External-facing functionality

- When a session's exec exits, the container is stopped only if no live exec sessions remain in the container. Any live session — another `onbox`/`netbox`/`offbox` terminal session, a `-c` command exec, a concurrent `setup.sh` exec, or a running `sync` exec — defers the stop.
- The last session to exit stops the container, whichever one started it and whatever the start/exit interleaving.
- Single-session behaviour is unchanged: the session's exit still stops the container (no sessions remain).
- If the exec-session listing is unavailable or fails, preserve the current behaviour (stop unconditionally) so old podman versions do not leave containers running forever.

## Key internal design (per the selected choice [concurrent-session-stop-mechanism](../../choices/concurrent-session-stop-mechanism.gen.md))

- The container's remaining exec sessions are enumerated with `podman exec list <container>` after this session's own exec has terminated; when the listing shows no sessions, the container is stopped, otherwise it is left running. Counting podman's own exec sessions means sessions opened outside `exec_in_container` (e.g. `sync`) also defer the stop, and no talkbox-side session registry is needed.
- `exec_in_container` keeps returning the exec's exit status; only the unconditional `stop_container` after the exec becomes conditional on the session count. `stop_container` callers elsewhere (`stop_and_die`, `rollback_creation_and_die`, `run_recreate`'s final stop) are unchanged per [failure-stop-semantics-under-concurrency](../../choices/failure-stop-semantics-under-concurrency.gen.md).
- Implementation must verify the `podman exec list` output format against the installed podman version and the reference docs in `.llm/ref/podman.docs` (including the `--no-session` option's effect on session visibility) and count sessions excluding the table header; a listing failure or unsupported subcommand falls back to an unconditional stop.

## Files to be created or modified

- `lib/containers.sh` — `exec_in_container` gates its trailing `stop_container` on the exec-session count; a small helper queries the container's live exec sessions and decides the stop.
- `test/unit/helpers.bash` — the podman shim gains an env-driven `exec list` response (a count/session listing controlled by a `PODMAN_*` variable) so unit tests can stage concurrent sessions.
- `test/unit/containers.bats` — unit tests for the session-count decision and the conditional stop.
- `test/e2e/lifecycle.bats` (or `onbox.bats`) — concurrent-session e2e tests.
- `MAP.gen.md` — updated entry for the stop-on-last-session behaviour in `lib/containers.sh`.

## Relevant files to read during implementation

- `lib/containers.sh` (`exec_in_container`, `stop_container`, `run_container`)
- `.llm/gen/issues/concurrent-session-exit-stops-container.gen.md` and `.llm/gen/reviews/multi-terminal-container-sessions.gen.md`
- `test/unit/helpers.bash` (`make_podman_shim`), `test/unit/containers.bats`, `test/e2e/lifecycle.bats`, `test/e2e/helpers.bash` (logging-delegate shim for e2e)
- `.llm/ref/podman.docs/podman-exec.1.md.in` (exec session model, `--no-session`, `podman container cleanup --exec`)

## Tests

- Unit tests (extend `test/unit/containers.bats`): the shim's `exec list` staged with zero remaining sessions results in `podman stop`; staged with one or more remaining sessions results in no stop; the exec's own exit status still propagates; a failing/unsupported `exec list` falls back to stopping.
- E2e tests (`test/e2e/lifecycle.bats`, driven per SPEC's systemd-run and `-c --noninteractive` conventions): a long-running first session (`sleep` via `onbox -c --noninteractive`) survives a second short session exiting; the container keeps running after the second session exits and stops after the first (last) session exits; ordering variation with the short session first.
