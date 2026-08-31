# Phase 8c: Bring `helpers.bash` files under `make lint` and `make format`

#flow/unified #model/default

## Specification

This phase resolves the issue [helpers.bash files are excluded from make lint and make format](../../issues/helpers-bash-excluded-from-lint-format.gen.md).

It does not implement any aspect of `SPEC.md` or `SPEC.gen.md`; it is a tooling/quality fix to the test harness.

## Aspects implemented

- `test/unit/helpers.bash` and `test/e2e/helpers.bash` become part of the `SHELL_SCRIPTS` set, so `make lint` (shellcheck) and `make format` (shfmt) cover them.
- The two helper files are brought into shfmt compliance.
- Shellcheck findings in those files are suppressed where they are false positives or intentional patterns, using the same suppression style already used in the `.bats` files.

## Aspects deferred

None.

## External-facing functionality

No change to talkbox runtime behaviour. The change is observable only via the `make lint` and `make format` targets, which now also check and format the two `helpers.bash` files.

## Files to be created

None.

## Files to be modified

- [test/runner.mk](../../../test/runner.mk) — extend `SHELL_SCRIPTS` to include `test/unit/helpers.bash` and `test/e2e/helpers.bash` (either by listing them explicitly or by a glob such as `test/**/helpers.bash`, taking care that the chosen glob still works with the existing make/shell expansion).
- [test/unit/helpers.bash](../../../test/unit/helpers.bash) — apply `shfmt -w`; add any shellcheck directives required for findings surfaced once lint runs against it.
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — apply `shfmt -w` (e.g. `((SD_TIMEOUT > 0))` spacing); add `# shellcheck disable=...` directives for the nameref false positives (SC2034 on `pid_ref`/`port_ref`) and intentional single-quoted `bash -c` scripts (SC2016 in `run_onbox_noninteractive` and `run_talkbox`), mirroring the inline suppressions used in the e2e `.bats` files.

## Relevant files to read during implementation

- [test/runner.mk](../../../test/runner.mk) — current `SHELL_SCRIPTS` definition.
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) and [test/unit/helpers.bash](../../../test/unit/helpers.bash) — files to bring under coverage.
- Existing `.bats` files in `test/e2e/` and `test/unit/` (e.g. `test/e2e/lifecycle.bats`, `test/e2e/netbox-offbox.bats`, `test/unit/netbox-offbox.bats`) for the established `# shellcheck disable=...` patterns.

## Key internal interfaces

No interface changes. The only interface touched is the `SHELL_SCRIPTS` make variable in `test/runner.mk`, consumed by the `lint` and `format` targets.

## Tests

This phase introduces no new testable behaviour; it is a tooling fix verified by the linter/formatter themselves. No unit or end-to-end tests are required.

The implementation must be verified by running, after the change:

- `make lint` exits successfully against the expanded `SHELL_SCRIPTS` set.
- `make format` exits successfully and leaves no diff (i.e. `shfmt -d` is clean) against the two helper files.
