# `MAP.gen.md` is missing implemented core test files

`MAP.gen.md` describes itself as a map of implemented core files, and `AGENTS.md` requires every implemented core file to be added to the map. The test harness section of the map lists only `Makefile`, `test/runner.mk`, `test/run-suite.sh`, `test/lib.bash`, `test/unit/smoke.bats`, `test/unit/parse-tap.bats`, `test/e2e/smoke.bats`, `test/e2e/host_http_server.py`, `test/canary/false.bats` and `test/timeout/hang.bats`, but the following implemented harness files are absent:

- `test/unit/helpers.bash`
- `test/e2e/helpers.bash`
- `test/unit/bashrc.bats`, `common.bats`, `containers.bats`, `git.bats`, `git-transport.bats`, `lifecycle.bats`, `merge.bats`, `mounts.bats`, `naming.bats`, `netbox-offbox.bats`, `network.bats`, `options.bats`
- `test/e2e/deny-allow.bats`, `git-identity.bats`, `git-transport.bats`, `lifecycle.bats`, `merge-sync.bats`, `netbox-offbox.bats`, `onbox.bats`

Both `helpers.bash` files are referenced by `test/runner.mk`'s `SHELL_SCRIPTS` (so they are clearly considered core by the lint/format targets), yet they and most of the suite they support cannot be discovered from the map.

Files causing the issue:

- `MAP.gen.md` (stale test-harness section)
- the unlisted files above

Suggested fix: add a map entry (link + 1-2 sentence description) for each missing file. Related: [duplication and abstraction review](../reviews/duplication-abstraction-review.gen.md) recommends consolidating several of these files' shared helpers, which would be a natural moment to refresh the map.
