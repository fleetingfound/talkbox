# Tests: Phase 6a e2e `--port` TOCTOU fix

Linked plan: [phase-6a-e2e-port-toctou-fix.gen.md](../plans/phase-6a-e2e-port-toctou-fix.gen.md)

Summary: this phase is a test-quality fix (per [Choice: Fixing the TOCTOU race in `free_host_port`](../choices/e2e-port-toctou-fix.gen.md), Option A) which replaces the probe-then-rebind pattern in the e2e `--port` test with a single port-0 server that holds its listening socket for its whole lifetime, eliminating the close-then-rebind race described in [Issue: E2e `--port` test has a TOCTOU race in `free_host_port`](../issues/e2e-port-test-toctou-race.gen.md); no implementation or user-facing behaviour changes, and the suite continues to pass deterministically.

## New tests

- `test/e2e/host_http_server.py` — a new standalone server script used by the e2e `--port` test. It binds a `socket.socket()` to `('127.0.0.1', 0)`, prints the kernel-assigned port as its sole stdout line (flushed), then wraps the already-bound socket in an `http.server.ThreadingHTTPServer` subclass (overriding `server_bind()` to adopt the pre-bound socket) and serves the directory given as `argv[1]`. The listening socket is held by the server process for its entire lifetime, so there is no window in which another host process can claim the port.
- `test/e2e/helpers.bash` — `start_host_http_server <directory> <pid-var> <port-var>`, a new helper that launches `test/e2e/host_http_server.py` in the background, waits for the port line to appear in a temporary capture file, and reports both the background PID and the bound port to the caller via namerefs. The caller remains responsible for `kill` on teardown, matching the existing `HOST_SRV_PID` pattern.

## Tests edited

- `test/e2e/lifecycle.bats` — `onbox --port makes a host port reachable inside the container` is rewritten to call `start_host_http_server "$www" srv port` instead of `port="$(free_host_port)"` followed by a separate `python3 -m http.server "$port" ... &`, and to read the port from the server's own first stdout line. The rest of the test is unchanged in shape: the `command -v python3` skip guard, the wait-for-`curl` loop, the `onbox --port "$port" -c --noninteractive` curl invocation, the `port-marker` assertion, and the explicit `kill "$srv"` / `rm -rf "$www"` teardown. It fails against the previous implementation only intermittently: between `free_host_port`'s `s.close()` and the server's later bind, another host process can claim the port, so the wait-for-`curl` loop times out and the in-container curl fails (observed as occasional 56/57 e2e results).

## Tests removed

- `test/e2e/helpers.bash` — `free_host_port` is removed. It fails against the implementation by construction of the race: it binds a probe socket to port 0, reads the assigned port, and closes the socket, after which nothing holds the port until the test's HTTP server rebinds it, leaving a close-then-rebind window for a port collision. The issue's affected-files list confirms `free_host_port` had no caller other than the `--port` e2e test, so it is replaced outright by `start_host_http_server` rather than retained.
