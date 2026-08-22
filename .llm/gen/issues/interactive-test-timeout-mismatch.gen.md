# Issue: interactive e2e test has inconsistent timeouts

## Affected files

- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats) - `onbox starts an interactive shell that exits via exit`
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) - `sdrun` default `SD_TIMEOUT=60`

## Description

The interactive e2e test embeds an `expect` script with `set timeout 90`, but invokes it via `sdrun` (which defaults to `SD_TIMEOUT=60`, used as `RuntimeMaxSec=60`). The `systemd-run` service is therefore configured to kill the session at 60 seconds, while `expect` would only declare a timeout at 90 seconds.

Consequently:

- `expect`'s own timeout diagnostic (`TIMEOUT waiting for interactive shell`) can never fire, because `systemd-run` kills the service first.
- The effective timeout is 60s, not the 90s the `expect` script claims.
- The test currently passes only because container startup takes ~0.5s. If startup ever exceeds 60s the failure mode would be an opaque systemd kill rather than `expect`'s clear message.

## Suggested fix

Align the two timeouts. Either:

- invoke `SD_TIMEOUT=120 sdrun expect ...` in the test so systemd allows expect's 90s timeout to fire, or
- reduce `set timeout` in the `expect` script to a value below 60s (e.g. 30s).

## Related

- [Review: Phase 1 onbox test suite](../reviews/phase-1-onbox-test-suite.gen.md)
