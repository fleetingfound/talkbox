# Choice: Fixing the TOCTOU race in `free_host_port`

## Context

The e2e `--port` test in [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) obtains a "free" host port via `free_host_port` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash), which binds a socket to port 0, reads the assigned port, closes the socket, and prints the port. The test then starts `python3 -m http.server` on that port. In the window between the probe socket closing and the HTTP server rebinding, another host process can claim the port, producing the intermittent 56/57-vs-57/57 flakiness described in [the issue](../issues/e2e-port-test-toctou-race.gen.md).

The root cause is the *probe-then-rebind* pattern, not the language used. The cleanest fixes eliminate the probe rather than narrowing the window.

## Options

### Option A — Server binds to port 0 directly, no probe (Recommended)

Replace `free_host_port` and the separate `python3 -m http.server "$port"` invocation with a single short Python script (inline heredoc or a small helper file) that:

1. binds a `socket.socket()` to `('127.0.0.1', 0)`,
2. prints the assigned port (the only line on stdout),
3. wraps that already-bound socket in `http.server`/`socketserver` and serves the given directory.

The listening socket is held by the server process for its entire lifetime, so there is no close-then-rebind window. The test reads the port from the server's first stdout line, then proceeds as today (wait-for-curl loop, then invoke `onbox --port`).

- Eliminates the race by construction.
- Stays within the existing `python3` dependency (the test already skips when `python3` is absent).
- Minimal, self-contained, no output-format parsing beyond a single integer line we control.

### Option B — Hold the probe socket open and pass its FD to the server

`free_host_port` keeps the socket bound and exposes its file descriptor. A custom server script accepts the pre-bound FD and uses it directly as the listening socket (e.g. inject `sock` into `socketserver.TCPServer`). The probe socket is never closed before the server takes it over.

- Eliminates the race.
- More moving parts than A (FD inheritance across `systemd-run` and subshells, FD scoping) with no real advantage, since the server still has to be a custom script — at which point binding port 0 inside it (Option A) is simpler.

### Option C — Retry loop on bind failure

Leave `free_host_port` unchanged. Wrap the server start and the existing wait-for-curl probe in a retry loop: on failure (server never comes up / `curl` never connects within the budget), discard the port, obtain a new one, and retry up to N times.

- Trivial diff, test body only.
- Does **not** eliminate the race — only recovers from it. Under contention retries can still be exhausted, and a transient bind failure is indistinguishable from a real regression. The issue text rates this inferior to A.

### Option D — Non-Python server via `socat`

Run `socat -d -d TCP-LISTEN:0,fork,reuseaddr,bind=127.0.0.1 EXEC:'<responder>'` and parse the bound port out of socat's `-d -d` output. The `EXEC:` responder emits a minimal HTTP response reading the marker file.

- Removes Python from the *server* side; the skip guard would become `command -v socat`.
- Depends on parsing socat's debug-output wording; the HTTP file responder must be hand-written in the `EXEC:` snippet. More fragile and more code than A, for a benefit (no Python) the rest of the suite does not need.

### Option E — `python3 -m http.server 0` with banner parsing

Start `python3 -m http.server 0 --bind 127.0.0.1 --directory "$www"` in the background and recover the port by parsing its first stderr line (`Serving HTTP on 127.0.0.1 port NNNN`). The server holds the socket, so there is no race.

- No probe, no custom script.
- Depends on the exact wording of `http.server`'s banner, which has varied across Python versions. More fragile than A, where the printed port is under our control.

## Recommendation

**Option A.** It removes the race by construction, keeps the existing Python dependency, and is shorter and more robust than B/D/E. Option C is acceptable as a stopgap but does not actually fix the defect.

## Selected option

**Option A — Server binds to port 0 directly, no probe.**

Replace `free_host_port` and the separate `python3 -m http.server "$port"` call in the `--port` e2e test with a single short Python invocation that binds a socket to `('127.0.0.1', 0)`, prints the assigned port as the sole stdout line, and then serves the given directory using that already-bound socket. The listening socket is held by the server process for its entire lifetime, eliminating the close-then-rebind race by construction. The existing `command -v python3 || skip` guard is retained.
