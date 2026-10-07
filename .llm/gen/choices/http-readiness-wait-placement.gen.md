# HTTP readiness wait placement

How the four hand-rolled HTTP-server readiness poll loops in `test/e2e/deny-allow.bats` (×3) and `test/e2e/lifecycle.bats` (×1) are consolidated (review §14).

Each loop retries a `curl` against the started host server's marker URL up to 20 times with 0.5s sleeps, always immediately after `start_host_http_server` (which itself already polls for the server's printed port line).

## Options

### A. Standalone `wait_for_http` helper (Recommended)

A `wait_for_http <url>` helper in `test/e2e/helpers.bash` (same retry budget and sleep as the current loops), called explicitly after `start_host_http_server`.

- Pros: keeps server start and readiness separate concerns; usable against any URL (e.g. the IPv6 variant binds a different address); the polling budget stays adjustable per call site.
- Cons: one extra call line per test.

### B. Built into `start_host_http_server`

Selected: **A. Standalone `wait_for_http` helper.**

Fold the readiness wait into `start_host_http_server`, either always or behind an option, so the function returns only once the server responds.

- Pros: no call-site changes beyond removing the loops.
- Cons: `start_host_http_server` already has a nameref-heavy signature and an internal port-line poll; layering a second poll inside it couples bind-readiness with HTTP-path readiness, and the served URL/marker path would have to be assumed or passed in.
