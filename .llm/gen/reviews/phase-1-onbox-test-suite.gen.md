# Review: Phase 1 onbox test suite

Related test doc: [phase-1-onbox-minimal.gen.md](../tests/phase-1-onbox-minimal.gen.md)
Related plan: [phase-1-onbox-minimal.gen.md](../plans/phase-1-onbox-minimal.gen.md)
Related spec: [SPEC.md](../../../SPEC.md)

## Test execution results

| Suite | Command | Result |
|---|---|---|
| Unit | `make test-unit` | 29/29 pass (4 files) |
| End-to-end | `make test-e2e` | 10/10 pass (2 files) |

The e2e-invoked `talkbox.sh onbox` commands were also run directly, each wrapped in `systemd-run --user --wait --collect --pipe -p RuntimeMaxSec=60 -p KillMode=control-group` per the spec's podman-invocation rule. All six noninteractive scenarios (working directory, host-visible file write, internet access, global dotfiles, project-dotfiles override, `onbox` symlink invocation) and the `expect`-driven interactive session reproduced the behaviour the e2e suite asserts.

## Does the suite accurately and meaningfully capture the intended behaviour?

Largely yes, with caveats. The suite covers the Phase 1 scope of `SPEC.md` reasonably: naming helpers, option parsing, the assembled `podman` argument list, and the externally-observable onbox behaviours (workdir, host-writable worktree, internet, dotfile copy/override, symlink dispatch, interactive shell). The interface contract documented in [phase-1-onbox-minimal.gen.md](../tests/phase-1-onbox-minimal.gen.md) matches the implemented `lib/*.sh` and `talkbox.sh`.

However, several assertions are too loose to pin the behaviour they claim to pin, and a few meaningful behaviours are entirely uncovered. These are detailed below as "Significant improvements". Two concrete defects in existing tests are recorded as issues:

- [issue: interactive e2e test has inconsistent timeouts](../issues/interactive-test-timeout-mismatch.gen.md)
- [issue: unit terminal-allocation assertion is too loose](../issues/terminal-allocation-assertion-too-loose.gen.md)

## Critical review of `.llm/gen/tests/phase-1-onbox-minimal.gen.md`

The document is accurate in its counts and descriptions. Counting the tests it claims: 7 (naming) + 6 (options) + 11 (containers) + 7 (e2e onbox) = 31 new tests, matching the doc. The interface-contract section correctly reflects the implemented functions and their signatures.

The doc's weaknesses are omissions rather than inaccuracies:

- It does not acknowledge that the terminal-allocation assertion is too permissive (see [issue: unit terminal-allocation assertion is too loose](../issues/terminal-allocation-assertion-too-loose.gen.md)).
- It does not note that the interactive `sdrun` timeout (60s) is shorter than the embedded `expect` timeout (90s), so the systemd service would kill the session before `expect`'s own timeout fires (see [issue: interactive e2e test has inconsistent timeouts](../issues/interactive-test-timeout-mismatch.gen.md)).
- It frames the tests as fixing the interface contract, but several contract details are under-specified by the tests (e.g. unknown-option rejection, `--rm` presence, dispatcher error paths).

## Significant improvements

### 1. Tighten the terminal-allocation assertion (issue)

`containers.bats::onbox interactive plan allocates a terminal` accepts any of `--interactive`, `-it`, `-i`, `-it`, `--tty`, `-t` as sufficient. An implementation that emitted only `-i` (no tty) would pass, yet would not allocate a proper terminal and would degrade the interactive shell. The test should require both an interactive flag and a tty flag (the implementation emits `--interactive` and `--tty` on separate lines; the test should assert both). See [issue: unit terminal-allocation assertion is too loose](../issues/terminal-allocation-assertion-too-loose.gen.md).

### 2. Fix the interactive test timeout mismatch (issue)

The `expect` script sets `set timeout 90` while `sdrun` defaults to `SD_TIMEOUT=60`, so `systemd-run`'s `RuntimeMaxSec=60` kills the service before `expect`'s 90s timeout can fire. The test currently passes only because container startup is ~0.5s; if startup ever exceeds 60s the failure mode would be a systemd kill rather than `expect`'s clear timeout diagnostic. Align the two (e.g. `SD_TIMEOUT=120 sdrun expect ...`) or lower the `expect` timeout below 60s. See [issue: interactive e2e test has inconsistent timeouts](../issues/interactive-test-timeout-mismatch.gen.md).

### 3. Add a unit test for unknown-option rejection

`lib/options.sh` returns 2 and prints `talkbox: unknown option: <opt>` for any `-*` argument not in `{--interactive,--noninteractive,-c,--command}`. No test in `options.bats` captures this. It is a meaningful, spec-relevant behaviour (the parser must reject unknown flags rather than silently treating them as the command). A test like `run parse_onbox_options --bogus; [[ "$status" -eq 2 ]]` would close the gap.

### 4. Add a test for dispatcher error paths

`talkbox.sh` rejects `netbox`/`offbox` with exit 1 ("not implemented yet") and unknown containers with exit 2. Neither path has any test. A lightweight test invoking `talkbox.sh offbox` and `talkbox.sh bogus` and asserting the exit code and stderr message would meaningfully capture the dispatcher contract. This belongs at the e2e level (it invokes the script) or as a sourced unit test of the dispatch logic.

### 5. Assert `--rm` is present in the plan

`plan_onbox` emits `--rm`, which is important for not leaving containers lingering after exit. No unit test in `containers.bats` asserts its presence. An e2e test could additionally verify that no `onbox` container remains after a noninteractive run (e.g. `podman ps -a --filter name=...` is empty). The current suite never verifies container cleanup.

### 6. Cover `--command` (long form) and `-c --interactive` at the e2e level

The e2e suite exclusively exercises `-c --noninteractive <cmd>`. The spec's command-execution section also defines `--command <cmd>` (long form) and the default `-c --interactive <cmd>` behaviour. Unit tests cover the parsing of these, but no end-to-end test confirms they actually drive the container. An `expect`-driven e2e test for `onbox -c --interactive 'echo X'` that sends `exit` and observes `X` would strengthen coverage of [SPEC.md §command execution](../../../SPEC.md).

### 7. Verify read-only mounts are actually read-only

The e2e tests confirm that dotfiles are *copied* into `/home/dev/`, but never verify that the bind-mounts themselves are read-only (e.g. that `touch /talkbox/dotfiles.global/probe` fails). SPEC.md mandates these mounts be read-only bind-mounts. A one-line assertion inside the noninteractive container would capture the mount permission, not just the copy semantics.

### 8. Question the planner-vs-executor dotfiles-existence split

`plan_onbox` always emits the `-v $project/.dotfiles:/talkbox/dotfiles.project:ro` line, even when `.dotfiles` does not exist on the host; `run_onbox` then filters the line out. SPEC.md says project dotfiles are mounted "when it exists on the host". The unit test for `plan_onbox` therefore asserts output that does not reflect what `podman run` actually receives. Either move the existence check into `plan_onbox` (so the planner's output is the truthful podman argument list) or add a unit test that documents the filtering behaviour of `run_onbox` explicitly. The current split makes the planner output a leaky abstraction.

### 9. Strengthen `base_image_name`

`naming.bats::base_image_name returns a non-empty stable name` only checks non-emptiness and idempotence. The plan fixes the image name as `talkbox/base:latest` (and `lib/containers.sh::ensure_base_image` depends on this exact value). Asserting the literal value would pin the contract that `ensure_base_image` and `plan_onbox` rely on.

### 10. Note the network dependency of the internet test

`onbox container has internet access` curls `https://example.com`. Internet access is a spec requirement for `onbox`, so the dependency is defensible, but the test will fail in any offline CI environment. A short note in the test (or a `skip` when the host itself has no connectivity) would prevent confusing failures. This is a minor robustness improvement, not a correctness issue.

## What the suite does well

- The unit/e2e split is clean: pure logic (naming, options, planner output) is pinned by fast unit tests; podman-invoking behaviour is covered by e2e under `systemd-run`.
- The `sdrun` helper correctly implements the spec's `RuntimeMaxSec`/`KillMode=control-group` wrapping for individual podman-invoking calls, separate from the suite-level wrapping in `test/run-suite.sh`.
- `mk_talkbox` copies the implementation into a throwaway directory, giving e2e tests isolation from the real repo.
- The `expect`-driven interactive test exercises the default-shell path that noninteractive tests cannot reach.
- The harness smoke tests (run-record writing, make-target exposure, timeout/timeout-canary) give confidence in the test infrastructure itself.
