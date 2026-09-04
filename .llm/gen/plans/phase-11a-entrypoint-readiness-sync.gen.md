# Plan: Phase 11a — Entrypoint readiness synchronization (tmpfs sentinel)

#flow/redgreen #model/default

## Specification scope

No aspect of `SPEC.md` / `SPEC.gen.md` is altered. This resolves the open issue
[E2e commands executed on a freshly started container race the entrypoint](../issues/e2e-fresh-container-exec-races-entrypoint.gen.md),
per the selected design in [Entrypoint readiness synchronization mechanism](../choices/entrypoint-readiness-sync.gen.md)
(Option A — tmpfs sentinel file). The readiness synchronization is an
implementation detail not prescribed by the specification; the SPEC describes
what the entrypoint does on start, not how the executors coordinate with it.

## To be implemented

- Add a `--tmpfs /run/talkbox` flag to the argument lists built by the three
  persistent-container planners in [lib/containers.sh](../../../lib/containers.sh):
  - `plan_onbox` (covers `run_onbox`, `plan_recontain`, `plan_rebuild`).
  - `plan_netbox` (covers `run_netbox`, `plan_netbox_recontain`,
    `plan_netbox_rebuild`, `create_netbox`).
  - `plan_offbox` (covers `run_offbox`, `plan_offbox_recontain`,
    `plan_offbox_rebuild`, `create_offbox`).
- In [image/entrypoint.sh](../../../image/entrypoint.sh), as the final action
  before the `exec` lines, write a sentinel file at `/run/talkbox/ready` (the
  `/run/talkbox` directory is created by the tmpfs mount; the entrypoint should
  `mkdir -p` it defensively in case the mount is absent, e.g. in one-shot
  containers).
- In [lib/containers.sh](../../../lib/containers.sh), add a readiness-wait
  helper function that, given a container name, runs a bounded `podman exec`
  polling loop for the sentinel file. The helper should use a single `podman exec`
  invoking an internal bash loop (e.g. `for ((i=0; i<N; i++)); do [[ -f
  /run/talkbox/ready ]] && exit 0; sleep 0.1; done; exit 1`) with a total
  timeout of approximately 15 seconds. If the timeout expires, the helper
  should call `die` with a descriptive message.
- Call the readiness-wait helper in `run_onbox`, `run_netbox` and `run_offbox`,
  after `podman start "$ctr"` and before the user-command `podman exec`. The
  helper must NOT be called in the one-shot container paths (`plan_volume_populate`,
  `container_sync_cmd` non-running path) since those run the entrypoint+command
  atomically via `podman run`.

## To be deferred

- Applying the readiness wait to the `container_sync_cmd` exec path (used by
  `run_sync_in_container` when the persistent container is running). In practice
  the container is already running from a prior `run_*` call whose entrypoint
  has long completed, so the race does not arise. If it proves necessary in
  future, the same helper can be inserted there.
- Making the readiness timeout configurable via an environment variable. The
  fixed 15-second bound is sufficient for all known scenarios.
- Applying the tmpfs mount to one-shot `podman run --rm` containers. They do
  not use `podman exec` and the entrypoint runs the command itself after
  setup, so no race exists.

## External-facing functionality

Commands run via `onbox -c`, `netbox -c` or `offbox -c` (interactive or
noninteractive) no longer intermittently fail due to racing the entrypoint's
start-up work. Git commands inside a freshly started container always execute
after the entrypoint has completed dotfiles copy, git identity config writes,
and gitdir-volume `git init`/`git fetch host`/`git reset --mixed`. If the
entrypoint fails to signal readiness within the timeout, the user sees a clear
`talkbox:` error message instead of a cryptic git failure.

## Files to be created

- None.

## Files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — `plan_onbox`, `plan_netbox`,
  `plan_offbox` (add `--tmpfs`), `run_onbox`, `run_netbox`, `run_offbox` (add
  readiness-wait call), and the new readiness-wait helper.
- [image/entrypoint.sh](../../../image/entrypoint.sh) — add the sentinel write
  before the `exec` lines.
- [test/unit/containers.bats](../../../test/unit/containers.bats) — existing
  planner unit tests, where `--tmpfs /run/talkbox` assertions are added.
- [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) —
  existing netbox/offbox planner unit tests, where `--tmpfs` assertions are
  added.
- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats), [test/e2e/git-identity.bats](../../../test/e2e/git-identity.bats),
  [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats) — existing
  e2e tests that exercise the race-prone paths; must continue to pass.

## Key internal interfaces

- A new readiness-wait helper in `lib/containers.sh` (e.g.
  `wait_for_entrypoint <ctr>`) that runs a bounded `podman exec` poll for
  `/run/talkbox/ready` and calls `die` on timeout. No nameref or array
  interface; takes the container name as its sole argument.
- `plan_onbox`, `plan_netbox`, `plan_offbox` — each gains the literal `--tmpfs`
  `/run/talkbox` element in its argument list. No signature change.
- [image/entrypoint.sh](../../../image/entrypoint.sh) — gains a `mkdir -p
  /run/talkbox && touch /run/talkbox/ready` (or equivalent) as its final
  pre-`exec` action.

## Tests

Requires tests, both unit and end-to-end.

- **Unit tests** (in [test/unit/containers.bats](../../../test/unit/containers.bats)
  and [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats)):
  assert that `plan_onbox`, `plan_netbox` and `plan_offbox` each emit `--tmpfs`
  and `/run/talkbox` in their argument lists. Assert that `plan_recontain`/
  `plan_rebuild` (onbox) and the netbox/offbox recontain/rebuild planners
  propagate `--tmpfs` (since they delegate to the base planners). The one-shot
  `plan_volume_populate` should continue to omit `--tmpfs`.
- **End-to-end tests:** the full e2e suite must continue to pass 67/67. The
  readiness synchronization is implicitly tested by every e2e test that runs a
  command in a freshly started container (git-identity, git-transport,
  lifecycle recontain, merge-sync). No new e2e test is strictly required, but
  an e2e test that verifies a git command succeeds immediately after container
  start (without a prior warm-up call) would directly exercise the fix and
  guard against regression.
