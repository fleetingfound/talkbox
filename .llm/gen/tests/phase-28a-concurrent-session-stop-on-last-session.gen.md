# Tests: Phase 28a stop the container only when no exec sessions remain

Red/green test suite for [the plan](../plans/phase-28a-concurrent-session-stop-on-last-session.gen.md), which gates the unconditional `stop_container` tail of `exec_in_container` in `lib/containers.sh` on the container's live `podman exec`-session count — enumerated from podman's own exec-session listing after the exiting session's own exec terminates — so the last session to exit stops the container regardless of start/exit ordering, single-session behaviour stays stop-on-exit, and an unavailable or failing listing falls back to the unconditional stop (implementing [the concurrent-session-exit-stops-container issue](../issues/concurrent-session-exit-stops-container.gen.md) per the [concurrent-session-stop-mechanism choice](../choices/concurrent-session-stop-mechanism.gen.md) with failure-path stops kept unconditional per the [failure-stop-semantics-under-concurrency choice](../choices/failure-stop-semantics-under-concurrency.gen.md)). No new issue documents were created for this phase.

No core files were edited. Only [test/unit/helpers.bash](../../../test/unit/helpers.bash), [test/unit/containers.bats](../../../test/unit/containers.bats), [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) and this document were changed. The plan also lists `MAP.gen.md` under "Files to be created or modified"; that update describes the implemented state and is left to the implementation phase.

## Mechanism verified against the installed podman

The plan instructs verifying the exec-session enumeration mechanism against the installed podman version and the reference docs before implementing. Verified on this host (podman 5.4.2):

- `podman exec list <ctr>` is not supported: podman parses `list` as the container name and fails with `Error: no container with name or ID "list" found` (exit 125). The subcommand is also absent from the vendored podman `main` docs in `.llm/ref/podman.docs`, and `--no-session` is not a `podman exec` option on this version.
- The documented equivalent exists and works: `podman inspect -f '{{json .ExecIDs}}' <ctr>` (see `podman-container-inspect.1.md.in`, `.ExecIDs`) enumerates the container's live exec sessions, including attached (non-detached) execs, and the exiting session's own ID is already removed when its `podman exec` returns (verified empirically with attached and detached execs, so the last session's listing correctly shows zero sessions).

Because of this, the unit-side staging deliberately serves the staged session listing for **both** candidate spellings — `podman exec list <ctr>` and an inspect invocation over a `.ExecIDs` format — so the tests pin the session-count decision without pinning the unsupported subcommand spelling, and the implementation remains free to use whichever podman invocation the verification step selects (directly or as a fallback chain). The e2e tests exercise the real podman enumeration end-to-end.

## New tests

All are new; each fails pre-implementation for a plan-relevant reason and passes once the plan is implemented.

### `test/unit/containers.bats`

Loop over `onbox`, `netbox`, `offbox` like the neighbouring `run_container` tests; each stages the exec-session listing through the podman shim.

- **`run_container consults the exec-session listing after the exec and stops when no sessions remain`** — with `PODMAN_EXEC_SESSIONS` staged empty, `run_container` must invoke the exec-session listing for the container strictly after its own `exec ... bash -c true` line and strictly before the `stop -t 5` line. Implements the plan's test item:
  > "the shim's `exec list` staged with zero remaining sessions results in `podman stop`"

  and pins the key-internal-design requirement that the listing be taken "after this session's own exec has terminated". Fails pre-implementation because no listing invocation is ever logged (`session_line` is empty).

- **`run_container leaves the container running when exec sessions remain after its exec exits`** — with one remaining session staged, the stop line must be absent while the listing invocation is present. Implements:
  > "staged with one or more remaining sessions results in no stop"

  Fails pre-implementation: the listing is never invoked, and the unconditional stop is still logged.

- **`run_container returns the exec exit status and defers the stop when exec sessions remain`** — a failing command (`PODMAN_FAIL_PATTERN`/`PODMAN_FAIL_CODE=7`) with one remaining session staged must still exit 7 while no stop is issued. Implements:
  > "the exec's own exit status still propagates"

  Fails pre-implementation at the listing/deferred-stop assertions (the exit status already propagates, but the stop is unconditional and the listing is absent).

- **`run_container stops the container when the exec-session listing fails or is unsupported`** — with `PODMAN_EXEC_SESSIONS_RC=125` (the staged listing invocation exits 125 with an "unsupported subcommand" stderr, for both spellings), the listing invocation must still be attempted and the `stop -t 5` line must follow it. Implements the plan's fallback requirement:
  > "a listing failure or unsupported subcommand falls back to an unconditional stop"

  and the external-facing item "If the exec-session listing is unavailable or fails, preserve the current behaviour (stop unconditionally)". Fails pre-implementation because the listing is never attempted at all.

- **`run_container leaves the container running when exec sessions remain after an interactive session`** — the no-command (`--interactive --tty /bin/bash`) exec branch with one remaining session staged must likewise not stop the container. Implements the external-facing item that "another `onbox`/`netbox`/`offbox` terminal session ... defers the stop". Fails pre-implementation for the same no-listing reason.

### `test/unit/helpers.bats` shim support (`test/unit/helpers.bash`)

- `make_podman_shim` gains the env-driven exec-session listing: `PODMAN_EXEC_SESSIONS` holds the staged live sessions (printed one per row for a `podman exec list <ctr>` invocation, as a JSON array for an inspect invocation whose arguments contain `ExecIDs`), and `PODMAN_EXEC_SESSIONS_RC`/`PODMAN_EXEC_SESSIONS_STDERR` make the listing invocation fail (defaulting to the podman 5.4.2-style "unsupported subcommand" text and exit 125). The branch is placed ahead of the generic `inspect` handler so an inspect over a `.ExecIDs` format reaches it. Implements the plan's fixture requirement:
  > "the podman shim gains an env-driven `exec list` response (a count/session listing controlled by a `PODMAN_*` variable) so unit tests can stage concurrent sessions"
- New helper `podman_session_line_no <ctr>` returns the podman-log line number of the listing invocation for a container (matching either spelling), or nothing when the listing was never invoked — this is what makes "the stop decision consulted podman's own exec-session listing" observable.

### `test/e2e/lifecycle.bats`

Both tests drive real concurrent sessions against real podman, per SPEC's `systemd-run` (via `sdrun`) and `-c --noninteractive` conventions, with background sessions in their own nested `sdrun` units (killed with the suite unit via `StopPropagatedFrom` and cleaned by `teardown_talkbox`'s `podman rm -f`). Readiness is observed through a marker file written by the session's exec into the bind-mounted worktree (`echo ready > .session-ready && sleep <n>`), which proves the session's *main* exec — not its `setup.sh` exec — is live before any assertion is made, keeping the stop-decision race window (acknowledged as milliseconds in the plan's choice document) out of the asserted path.

- **`onbox concurrent sessions: a short session exits without stopping a live longer session`** — a long first session (`sleep 30`, backgrounded) creates the container; a short second session (`true`) attaches and exits; the container must still be running with the first session's exec registered (`{{.State.Running}}` true, `.ExecIDs` non-empty), and only when the first (last) session exits does the container stop. Implements:
  > "a long-running first session (`sleep` via `onbox -c --noninteractive`) survives a second short session exiting; the container keeps running after the second session exits and stops after the first (last) session exits"

  Fails pre-implementation at the post-second-session running assertion (line 166): the short session's unconditional stop tears the container down under the live long session.

- **`onbox concurrent sessions: the container stops only after the last session exits when the short session starts it`** — ordering variation: the short session (`sleep 8`) creates and starts the container (the second session attaches only after `podman container exists` succeeds, avoiding the deferred create-rollback race), the long session (`sleep 25`) attaches while it is live; the short session exits with status 0, the container must still be running with the long session registered, and only the last (attaching) session's exit stops it. Implements:
  > "The last session to exit stops the container, whichever one started it and whatever the start/exit interleaving ... ordering variation with the short session first"

  Fails pre-implementation at the post-starter-exit running assertion (line 194).

## Edited tests

None. Every pre-existing unit test keeps passing under the planned behaviour because the shim stages no sessions by default (`PODMAN_EXEC_SESSIONS` unset yields a zero-session listing, so the conditional stop still fires), and the failure-path tests (`stop_and_die` for nft/setup failures) exercise paths the plan leaves unchanged:

> "`stop_container` callers elsewhere (`stop_and_die`, `rollback_creation_and_die`, `run_recreate`'s final stop) are unchanged"

Every pre-existing e2e test is single-session, which per the plan keeps stop-on-exit:

> "Single-session behaviour is unchanged: the session's exit still stops the container (no sessions remain)."

## Removed tests

None. No existing test is inconsistent with the plan document, `SPEC.md` or `SPEC.gen.md`: the exec-then-stop tail being refined is exactly the tail the existing `run_container` tests assert for the zero-remaining-sessions case, and no SPEC aspect addressed by this plan (concurrent sessions) was previously tested anywhere (per the multi-terminal review, "No unit or e2e test exercises two concurrent sessions").

## Observed red state (pre-implementation)

- `make test-unit`: 314 tests, 5 failures — exactly the five new unit tests, each failing at the plan-relevant "the exec-session listing was never invoked" / "the stop was issued despite remaining sessions" assertions; no unrelated test regressed.
- `make test-e2e`: 83 tests, 2 failures — exactly the two new e2e tests at the deferral assertions described above (earlier assertions — marker readiness, running container, short session's clean exit 0 — all pass, so the timing design is sound); no unrelated test regressed.
- `make lint` clean.
