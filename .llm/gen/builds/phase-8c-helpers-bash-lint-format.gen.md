# Phase 8c: Bring `helpers.bash` files under `make lint` and `make format`

Status: `SUCCESS`

This build implements [phase-8c-helpers-bash-lint-format.gen.md](../plans/phase-8c-helpers-bash-lint-format.gen.md), which brings `test/unit/helpers.bash` and `test/e2e/helpers.bash` under the `make lint` (shellcheck) and `make format` (shfmt) targets, resolving [helpers-bash-excluded-from-lint-format.gen.md](../issues/helpers-bash-excluded-from-lint-format.gen.md). It is a tooling/quality fix to the test harness and changes no talkbox runtime behaviour.

## Overview

- `test/runner.mk` - the `SHELL_SCRIPTS` set (consumed by the `lint` and `format` targets) now also lists `test/unit/helpers.bash` and `test/e2e/helpers.bash`, so the two helper files are checked by shellcheck and formatted by shfmt.
- `test/unit/helpers.bash` - added an inline `# shellcheck disable=SC1090` directive on the dynamic `source "$PROJECT_ROOT/lib/$lib"` (the sourced lib path cannot be statically resolved).
- `test/e2e/helpers.bash` - applied the single shfmt fix (`(( SD_TIMEOUT > 0 ))` → `((SD_TIMEOUT > 0))`) and added inline shellcheck suppressions mirroring the style already used in the `.bats` files: `SC2034` on the `pid_ref`/`port_ref` nameref writes (false positives; the variables are consumed by the caller through namerefs) and `SC2016` on the intentional single-quoted `bash -c` scripts in `run_onbox_noninteractive` and `run_talkbox`.

## Edited tests

The only edits under `test/` are to `test/runner.mk`, `test/unit/helpers.bash` and `test/e2e/helpers.bash`. Each is mandated by the plan document, which lists all three under "Files to be modified" and specifies the changes:

- "extend `SHELL_SCRIPTS` to include `test/unit/helpers.bash` and `test/e2e/helpers.bash` (either by listing them explicitly or by a glob such as `test/**/helpers.bash`, taking care that the chosen glob still works with the existing make/shell expansion)" - implemented by listing both files explicitly.
- "apply `shfmt -w`; add any shellcheck directives required for findings surfaced once lint runs against it" (unit helper) and "apply `shfmt -w` (e.g. `((SD_TIMEOUT > 0))` spacing); add `# shellcheck disable=...` directives for the nameref false positives (SC2034 on `pid_ref`/`port_ref`) and intentional single-quoted `bash -c` scripts (SC2016 in `run_onbox_noninteractive` and `run_talkbox`), mirroring the inline suppressions used in the e2e `.bats` files" (e2e helper).

The plan introduces no new testable behaviour ("No unit or end-to-end tests are required"), so no `.bats` tests were added or modified.

## Verification

- `make lint` - exit `0` with the expanded `SHELL_SCRIPTS` set.
- `make format` - exit `0` and leaves no diff (`shfmt -d test/unit/helpers.bash test/e2e/helpers.bash` is clean).
- `make test-unit` - exit `0`; 178/178 tests passed.
- `make test-e2e` - exit `0`; 60/60 tests passed.
