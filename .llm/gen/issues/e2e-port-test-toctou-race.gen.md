# Issue: E2e `--port` test has a TOCTOU race in `free_host_port`

## Affected files

- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — `free_host_port()`
- [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) — "onbox --port makes a host port reachable inside the container"

## Description

`free_host_port` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) asks the kernel for a free TCP port by binding a socket to port 0, reading the assigned port, closing the socket, and printing the port number:

```python
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
```

Between the `s.close()` and the test's subsequent use of the port (starting `python3 -m http.server` on it, then asking the container to `curl` it), another process on the host can claim the same port. This is a classic time-of-check-to-time-of-use (TOCTOU) race.

The "onbox --port" e2e test in [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) depends on this helper. Observed symptom: the e2e suite intermittently reports 56/57 passing (one failure) on some runs and 57/57 on others, with no code changes between runs. The flakiness is consistent with a port collision after `free_host_port` returns.

This is a test-quality issue, not an implementation bug — the `--port` feature itself works correctly when the port is genuinely free.

## Suggested fix

Hold the listening socket open across the lifetime of the test's HTTP server instead of closing it after probing. For example, return the file descriptor or a wrapper object that keeps the socket bound, and only close it once the test's HTTP server has taken over the port. Alternatively, retry the `python3 -m http.server` bind a few times on `Address already in use` errors before declaring failure.

A minimal fix is to bind the test's HTTP server to port 0 directly and read the actual bound port back from the server socket, eliminating the probe-then-rebind pattern entirely.

## Related

- [Review: current repository review](../reviews/repository-review.gen.md)
