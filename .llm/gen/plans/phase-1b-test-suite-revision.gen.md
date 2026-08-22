# Phase 1b: Test-suite revision — correctness, timeouts and coverage gaps

#flow/pin #model/default

## Scope

Addresses the remaining shortcomings identified by [Review: Phase 1 onbox test suite](../reviews/phase-1-onbox-test-suite.gen.md) and [Review: test suite timeout implementation](../reviews/test-suite-timeouts.gen.md) that were not resolved by [Phase 1a](phase-1a-planner-dotfiles-truthfulness.gen.md). All changes are to test files and the test harness; no production code is modified. Every change must pass against the existing implementation (as updated by Phase 1a).

The phase combines three groups of work:

1. **Test correctness and timeout harness fixes** — the two open issues against the Phase 1 suite and the timeout-harness refinements.
2. **Unit-test coverage gaps** — unknown-option rejection, `--rm` presence, `base_image_name` literal value, dispatcher unknown-container path.
3. **End-to-end coverage gaps and robustness** — `--command` long-form and `-c --interactive` e2e coverage, read-only mount verification, internet-test offline robustness.

### Implemented from SPEC.md

- [SPEC.md §testing](../../../SPEC.md): per-test `systemd-run` wrapping with `RuntimeMaxSec`/`KillMode=control-group` for podman-invoking tests, and suite-level wrapping.
- Tightening of the terminal-allocation contract implied by [SPEC.md §command execution](../../../SPEC.md) (interactive sessions require an allocated tty).
- [SPEC.md §command execution](../../../SPEC.md): `-c`/`--command`/`--interactive`/`--noninteractive` parsing, including rejection of unknown flags; `onbox --command <command>` (long form) and the default `onbox -c --interactive <command>` interactive execution.
- [SPEC.md §implementation](../../../SPEC.md): the dispatcher (`talkbox.sh onbox`/`netbox`/`offbox`/unknown) and the shared base image name contract that `ensure_base_image` and `plan_onbox` rely on.
- [SPEC.md §image and container management](../../../SPEC.md) (implicit): `--rm` semantics — containers should not linger after exit.
- [SPEC.md §dotfiles](../../../SPEC.md) / [SPEC.md §onbox](../../../SPEC.md): the global and project dotfiles bind-mounts are read-only bind-mounts.
- [SPEC.md §network](../../../SPEC.md): `onbox` allows internet access (with a host-connectivity-aware skip for offline environments).

### Deferred

- Dispatcher error-path coverage for `offbox`/`netbox` (which currently report "not implemented yet") — deferred until [Phase 3](phase-3-netbox-offbox.gen.md) implements those containers; only the `bogus` (truly unknown container) path is pinned here, per the user's instruction.

## External-facing functionality

None. No change to `talkbox.sh` or `lib/*.sh` behaviour. The test suite and harness are corrected and extended so that timeouts are consistent, the terminal-allocation assertion pins the intended behaviour, and the coverage gaps are closed.

## Files to create

None (all changes are to existing test/harness files).

## Files to read during implementation

- [test/unit/containers.bats](../../../test/unit/containers.bats) — the loose terminal-allocation assertion; planner tests (now operating against the truthful planner from Phase 1a).
- [test/unit/options.bats](../../../test/unit/options.bats), [test/unit/naming.bats](../../../test/unit/naming.bats), [test/unit/helpers.bash](../../../test/unit/helpers.bash) — existing unit-test style and `load_lib` helper.
- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats) — the interactive `expect` test with `set timeout 90`; existing e2e test style.
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — `sdrun` and the hardcoded `SD_TIMEOUT=60`; `run_onbox_noninteractive`, `mk_project`, `mk_talkbox`.
- [test/runner.mk](../../../test/runner.mk), [test/run-suite.sh](../../../test/run-suite.sh) — timeout defaults and `BATS_TEST_TIMEOUT` propagation.
- [lib/containers.sh](../../../lib/containers.sh) — confirms `plan_onbox` emits `--interactive` and `--tty` on separate lines (so the tightened assertion passes) and a `--rm` line; confirms mounts are emitted with `:ro`.
- [lib/options.sh](../../../lib/options.sh) — confirms unknown `-*` arguments return 2 and print `talkbox: unknown option: <opt>` to stderr; confirms `--command` long form and `-c --interactive` are supported.
- [lib/naming.sh](../../../lib/naming.sh) — confirms `base_image_name` prints `talkbox/base:latest`.
- [talkbox.sh](../../../talkbox.sh) — confirms the dispatcher's `*)` case prints `talkbox: unknown container: <name>` to stderr and exits 2 before any `podman` invocation.
- [Issue: unit terminal-allocation assertion is too loose](../issues/terminal-allocation-assertion-too-loose.gen.md), [Issue: interactive e2e test has inconsistent timeouts](../issues/interactive-test-timeout-mismatch.gen.md).
- [Review: Phase 1 onbox test suite](../reviews/phase-1-onbox-test-suite.gen.md), [Review: test suite timeout implementation](../reviews/test-suite-timeouts.gen.md).
- [SPEC.md §command execution](../../../SPEC.md), [SPEC.md §dotfiles](../../../SPEC.md), [SPEC.md §network](../../../SPEC.md).

## Key internal interfaces to be modified

### 1. Test correctness and timeout harness fixes

- [test/unit/containers.bats](../../../test/unit/containers.bats): `onbox interactive plan allocates a terminal` — replace the loose regex union (`--interactive|-it|-i|--tty|-t`) with an assertion that the planner output contains both an interactive flag line and a tty flag line (matching what `plan_onbox` emits: `^--interactive$` and `^--tty$`). The mirror negative test (`onbox noninteractive plan does not allocate a terminal`) may keep its union form since asserting absence of any is correct there.
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash): `SD_TIMEOUT` should be derived from `INDIVIDUAL_TEST_TIMEOUT` (defaulting to 60 when unset) and set to a few seconds less than `INDIVIDUAL_TEST_TIMEOUT` (e.g. `INDIVIDUAL_TEST_TIMEOUT - 5`) so that an inner `sdrun` `RuntimeMaxSec` fires before the outer `BATS_TEST_TIMEOUT`, yielding a clear podman-killed diagnostic rather than a simultaneous bats timeout. `INDIVIDUAL_TEST_TIMEOUT` must be exported/imported into the e2e environment (it is already exported by `test/runner.mk` and propagated by `run-suite.sh`).
- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats): the interactive `expect` test — align the `expect` `set timeout` with the (now derived) `SD_TIMEOUT`. Reduce `set timeout` to a value comfortably below `SD_TIMEOUT` (e.g. 30s with default `INDIVIDUAL_TEST_TIMEOUT=60`) so that `expect`'s own timeout diagnostic is the one that fires, not a systemd kill. Optionally pass `SD_TIMEOUT` explicitly if the derived default does not give enough headroom.
- [test/runner.mk](../../../test/runner.mk): a one-line note in the `help` target documenting that the per-test `BATS_TEST_TIMEOUT` is set only when tests are invoked via `make` (direct `bats` invocation has no per-test timeout), per timeouts-review refinement 4.

### 2. Unit-test coverage gaps

- [test/unit/options.bats](../../../test/unit/options.bats): add a test asserting `parse_onbox_options --bogus` returns exit code 2 and emits the `talkbox: unknown option:` message to stderr. (Use `run parse_onbox_options --bogus` and assert `$status` and `$output`/stderr.)
- [test/unit/containers.bats](../../../test/unit/containers.bats): add a test asserting the `plan_onbox` output contains a `--rm` line (e.g. `plan_line '^--rm$'`).
- [test/unit/naming.bats](../../../test/unit/naming.bats): tighten/replace `base_image_name returns a non-empty stable name` (or add alongside it) with an assertion that `base_image_name` prints the literal `talkbox/base:latest`, pinning the contract that `ensure_base_image` and `plan_onbox` depend on.
- New unit test for the dispatcher's unknown-container path: invoke the dispatcher's bogus path (e.g. `talkbox.sh bogus`) and assert exit code 2 and the `talkbox: unknown container:` stderr message. Because this path exits before any `podman` call, it does not require `sdrun`/`systemd-run` wrapping and may be tested at the unit level (it does not invoke podman). The test should follow the existing unit-test conventions; if the dispatch logic cannot be sourced as-is, invoking `talkbox.sh bogus` as a subprocess via the bats `run` primitive is acceptable since no podman is involved.

### 3. End-to-end coverage gaps and robustness

- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats) or a helper in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash):
  - Add an e2e test using the `--command` long form (e.g. `talkbox.sh onbox --command --noninteractive 'pwd'`) asserting the same working-directory behaviour as the existing `-c` test, confirming the long form drives the container end-to-end. (A small helper variant or inline `sdrun` invocation is acceptable.)
  - Add an `expect`-driven e2e test for `onbox -c --interactive '<cmd>'` that sends the command, observes its output, then sends `exit` and confirms the session exits. This covers the default interactive command-execution path that the current suite (which only exercises `-c --noninteractive`) does not reach.
- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats):
  - Add a test asserting the dotfiles bind-mounts are actually read-only inside the container — e.g. run a noninteractive command that attempts to write a probe file under `/talkbox/dotfiles.global/` (and, when `$PROJECT/.dotfiles` exists, `/talkbox/dotfiles.project/`) and assert the write fails (non-zero exit / "read-only file system"). This pins the `:ro` mount permission, not just the copy semantics.
  - Make the existing `onbox container has internet access` test robust to offline environments: skip (with a clear message) when the host itself has no connectivity, e.g. probe the host's connectivity first (a bounded `curl`/`getent`/similar) and `skip` if unavailable. The spec dependency on internet is retained; this only prevents confusing offline-CI failures.

## Tests

This phase is itself a test-only revision. Verification is by running the existing suites with the new/updated tests included:

- **Unit tests**: `make test-unit` — all unit tests pass, including the tightened terminal-allocation assertion (which must pass against the unchanged `plan_onbox`), the new unknown-option test, the `--rm` presence test, the `base_image_name` literal-value test, and the dispatcher unknown-container test.
- **End-to-end tests**: `make test-e2e` — all e2e tests pass, including the interactive `expect` test under the aligned timeouts, the `--command` long-form test, the `-c --interactive` `expect`-driven test, and the read-only mount verification test. The internet test passes when the host is online and skips cleanly when the host is offline.

No new production code is introduced by this phase.
