# Plan: Phase 6a — Fix e2e `--port` test TOCTOU race

#flow/pin #model/default

## Specification scope

This is a test-quality fix, not a feature change. No aspect of `SPEC.md` / `SPEC.gen.md` is altered and no implementation behaviour changes. It resolves the open issue [E2e `--port` test has a TOCTOU race in `free_host_port`](../issues/e2e-port-test-toctou-race.gen.md), per the selected design in [E2e --port TOCTOU fix](../choices/e2e-port-toctou-fix.gen.md) (Option A).

## To be implemented

Replace the probe-then-rebind pattern in the e2e `--port` test with a single Python server that binds to port 0 and holds the listening socket for its entire lifetime, eliminating the close-then-rebind race by construction.

Concretely:

- Remove `free_host_port` from `test/e2e/helpers.bash` (or replace it with a helper that starts the combined port-0 server and emits the port, depending on the cleaner shape — see below).
- In the `onbox --port makes a host port reachable inside the container` test in `test/e2e/lifecycle.bats`, replace the `port="$(free_host_port)"` + `python3 -m http.server "$port" ... &` sequence with one Python invocation that:
  1. binds a `socket.socket()` to `('127.0.0.1', 0)`,
  2. prints the kernel-assigned port as the sole stdout line,
  3. wraps that already-bound socket in `http.server`/`socketserver` and serves `--directory "$www"`.
- The test reads the port from the server's first stdout line, then proceeds exactly as today: wait-for-`curl` loop, then `onbox --port "$port" -c ... curl ...`, then assert `port-marker`.
- Keep the existing `command -v python3 >/dev/null 2>&1 || skip` guard.
- Keep the existing teardown (`kill "$HOST_SRV_PID"` / `rm -rf "$www"`); the server process lifecycle is unchanged in shape.

Preferred shape: a small helper function in `test/e2e/helpers.bash` (e.g. `start_host_http_server <directory>`) that launches the combined server in the background and writes the port to a caller-supplied variable, so the test body stays readable. Whether the helper returns the PID/port via stdout or a nameref is an implementation detail for the implementer.

## To be deferred

- Nothing. This is a self-contained, single-purpose fix.

## External-facing functionality

None — no user-facing behaviour changes. Only the e2e test harness changes.

## Files to be created

- None necessarily. If the implementer prefers a standalone server script over an inline heredoc, it may be placed at `test/e2e/host_http_server.py` and added to `MAP.gen.md`; an inline heredoc in `test/e2e/helpers.bash` is also acceptable.

## Files to read during implementation

- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — `free_host_port` to be removed/replaced.
- [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) — the `--port` test to be rewritten.
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) `sdrun` / teardown conventions, for consistent background-process handling.

## Key internal interfaces

- New test helper (if added): `start_host_http_server <directory>` (name indicative only) — starts the port-0 server in the background and reports both its PID and the bound port to the caller; the caller is responsible for `kill` on teardown (matching the existing `HOST_SRV_PID` pattern).
- `free_host_port` is removed; no other caller exists (confirmed by the issue's affected-files list).

## Tests

This plan *is* a test change. The relevant test is the e2e case itself; it must continue to pass reliably (no port collisions) across repeated runs:

- **Unit tests:** none required — this is e2e-only test harness.
- **End-to-end tests:** the `onbox --port makes a host port reachable inside the container` case in `test/e2e/lifecycle.bats` must still pass and must do so deterministically; run the full e2e suite multiple times to confirm the previous flakiness is gone.
