# Tests: Phase 1b test-suite revision — correctness, timeouts and coverage gaps

Linked plan: [phase-1b-test-suite-revision.gen.md](../plans/phase-1b-test-suite-revision.gen.md)

Summary: this phase is a test-only revision that fixes the terminal-allocation and interactive-timeout defects ([issue: unit terminal-allocation assertion is too loose](../issues/terminal-allocation-assertion-too-loose.gen.md), [issue: interactive e2e test has inconsistent timeouts](../issues/interactive-test-timeout-mismatch.gen.md)) raised by [Review: Phase 1 onbox test suite](../reviews/phase-1-onbox-test-suite.gen.md), applies the timeout-harness refinements from [Review: test suite timeout implementation](../reviews/test-suite-timeouts.gen.md), and closes the coverage gaps those reviews identified, all against the unchanged implementation.

## New tests

Unit tests (`test/unit/`):

- `test/unit/containers.bats` - `onbox plan emits --rm so the container is removed after exit` - asserts the planner output contains a `^--rm$` line, pinning the [SPEC.md §image and container management](../../../SPEC.md) `--rm` semantics that containers should not linger after exit.
- `test/unit/options.bats` - `unknown options are rejected with exit code 2 and a message` - `run parse_onbox_options --bogus`, asserting `$status -eq 2` and the `talkbox: unknown option: --bogus` message, pinning the [SPEC.md §command execution](../../../SPEC.md) rejection of unknown flags.
- `test/unit/smoke.bats` - `dispatcher rejects an unknown container name with exit code 2` - `run "$PROJECT_ROOT/talkbox.sh" bogus`, asserting exit code 2 and the `talkbox: unknown container: bogus` stderr message; this path exits before any `podman` invocation, so it is tested at the unit level.

End-to-end tests (`test/e2e/onbox.bats`):

- `onbox --command long form drives the container end-to-end` - invokes `talkbox.sh onbox --command --noninteractive 'pwd'` via `sdrun` and asserts the same `/working/<project-base>` working-directory behaviour as the existing `-c` test, covering the [SPEC.md §command execution](../../../SPEC.md) long form.
- `onbox -c --interactive runs a command and the session exits via exit` - `expect`-driven test which spawns `onbox -c --interactive "echo <marker>"`, observes the command's output, then sends `exit` and confirms the session exits, covering the default interactive command-execution path the suite previously did not reach.
- `onbox dotfiles global bind-mount is read-only inside the container` and `onbox dotfiles project bind-mount is read-only inside the container` - run a noninteractive `touch /talkbox/dotfiles.global/probe` (and `/talkbox/dotfiles.project/probe` with `$PROJECT/.dotfiles` created) and assert the write fails with a non-zero exit, pinning the `:ro` mount permission rather than just the copy semantics.

## Tests edited

Each edit is to a test or harness file whose previous form was defective against the project implementation:

- `test/unit/containers.bats` - `onbox interactive plan allocates a terminal` - the old assertion accepted any one of `--interactive|-it|-i|--tty|-t`, so an implementation emitting only `-i` (interactive without a tty) would have passed, failing to pin the terminal-allocation contract; it is tightened to require both a `^--interactive$` and a `^--tty$` line, which the unchanged `plan_onbox` emits. The mirror negative test keeps its union form since asserting the absence of any terminal flag is correct there.
- `test/unit/naming.bats` - `base_image_name returns a non-empty stable name` - the old test only checked non-emptiness and idempotence, so any constant non-empty name (e.g. `foo/bar:1`) would have passed, failing to pin the literal `talkbox/base:latest` value that `ensure_base_image` and `plan_onbox` depend on; it is replaced by `base_image_name prints the shared base image name talkbox/base:latest`, which asserts the literal value.
- `test/e2e/helpers.bash` - `SD_TIMEOUT` - previously hardcoded to `60`, so an `INDIVIDUAL_TEST_TIMEOUT` override left the inner `sdrun` `RuntimeMaxSec` inconsistent with the bats per-test timeout, and at the default both fired simultaneously (per timeouts-review refinements 1 and 2); it is now derived as `INDIVIDUAL_TEST_TIMEOUT - 5` (defaulting to 60 when unset, floored at 1) so the inner podman-kill diagnostic fires before the outer bats timeout.
- `test/e2e/onbox.bats` - `onbox starts an interactive shell that exits via exit` - `set timeout 90` exceeded the (now derived) `SD_TIMEOUT`, so `systemd-run`'s `RuntimeMaxSec` would have killed the session before `expect`'s own timeout diagnostic could fire (the opaque failure mode described in [issue: interactive e2e test has inconsistent timeouts](../issues/interactive-test-timeout-mismatch.gen.md)); reduced to 30s so `expect`'s diagnostic is the one that fires.
- `test/e2e/onbox.bats` - `onbox container has internet access` - previously failed confusingly in offline CI; it now probes the host's connectivity first with a bounded `curl` and `skip`s with a clear message when the host is offline, retaining the spec's internet dependency.
- `test/runner.mk` - the `help` target gains a one-line note documenting that the per-test `BATS_TEST_TIMEOUT` is set only when tests run via `make`; direct `bats` invocation has no per-test timeout (timeouts-review refinement 4).

## Tests removed

None. No pre-existing tests needed removal; every corrected test was fixed in place as described above.
