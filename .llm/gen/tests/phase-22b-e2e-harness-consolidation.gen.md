# Phase 22b: e2e setup/teardown consolidation and shared e2e helpers

Implements [phase-22b-e2e-harness-consolidation.gen.md](../plans/phase-22b-e2e-harness-consolidation.gen.md), which consolidates the e2e harness scaffolding — the per-file `setup()`/`teardown()` boilerplate into a shared `e2e_setup`/`e2e_teardown` pair with registration helpers, the per-file `volume_mountpoint`/`container_stopped` helpers, the four hand-rolled HTTP readiness loops into `wait_for_http`, the sixteen hand-rolled `sdrun bash -c` invocation sites into `run_talkbox`/`run_talkbox_symlink` (with an optional podman-shim PATH-prepend), and `mk_gpu_shim` plus the two inline logging shims into one parameterised `mk_podman_logging_shim` — across the seven e2e suites, with no change to any test's assertions and no change to any production file.

## New tests

None. The plan states that this phase is test-infrastructure restructuring only, with no new product behaviour and no new testable behaviour beyond what the existing e2e suite already captures; the entire e2e suite (77 tests) plus the unit suite (305 tests) is the safety net and passes unchanged.

## Tests edited

No test's assertions were edited, weakened or removed — every assertion in the seven converted suites is byte-identical to before. The edits below are scaffolding conversions inside or around the tests, each identified by the plan document:

- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats), [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats), [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats), [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats), [test/e2e/git-identity.bats](../../../test/e2e/git-identity.bats), [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats), [test/e2e/merge-sync.bats](../../../test/e2e/merge-sync.bats) — each file's `setup()`/`teardown()` became a thin wrapper over the shared `e2e_setup`/`e2e_teardown` pair (file-specific state kept in the wrapper: the deny-allow PATH export, initial commits, the `CTR`/`NETBOX_ROOT`/`PLAIN_CTR`/`BRANCH`/`GITDIR_VOL` variables), per the plan's shared-pair mechanism. Not superseded; no assertions changed.
- The three `deny-allow.bats` and one `lifecycle.bats` readiness poll loops became `wait_for_http <url>` calls with the same 20 × 0.5s retry budget; the tracked-server-PID pattern (`HOST_SRV_PID`) became `e2e_register_pid`/`e2e_clear_pids`, per the plan's readiness-wait and registration-helper mechanisms. Not superseded; no assertions changed.
- All sixteen hand-rolled `sdrun bash -c 'cd "$1" && …'` sites (onbox ×3, netbox-offbox ×2, deny-allow ×3, lifecycle ×7, git-identity ×1) became `run_talkbox` calls, with the symlink-invocation test moving onto the new `run_talkbox_symlink` helper and the shim sites using the new optional shim PATH-prepend (`e2e_use_podman_shim`), per the plan's run-wrapper mechanism; their stale `# shellcheck disable=SC2016` comments were removed. Not superseded; no assertions changed.
- The three inline podman-shim heredocs (`mk_gpu_shim` callers and the `git-identity.bats`/`deny-allow.bats` logging shims) became `mk_podman_logging_shim` calls — its stub-everything (`start exec stop`) and stub-nothing configurations preserve each original shim's observable log format and delegation contract, per the plan's logging-delegate mechanism. Not superseded; no assertions changed.
- `EXTRA_DIRS` registrations in `git-transport.bats` (×3) became mid-test `e2e_register_dir` calls; the per-file `volume_mountpoint`/`container_stopped` definitions were moved into the shared helpers, per the plan's §11/§15 scope. Not superseded; no assertions changed.

## Tests removed

None. The plan states that no tests are superseded or removed: the setup/teardown wrappers, the readiness poll loops and the hand-rolled `sdrun` invocations being replaced are scaffolding inside or around tests, not tests themselves.

## Verification

`make test-unit` (305/305), `make test-e2e` (77/77, 0 skips), `make lint` and `make format` all pass on the converted helpers and bats files.
