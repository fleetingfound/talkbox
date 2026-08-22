# Phase 1c: Scaffold refactor — array-based planner and style fixes

Status: `SUCCESS`

This build implements [phase-1c-scaffold-refactor.gen.md](../plans/phase-1c-scaffold-refactor.gen.md), which replaces the fragile text-protocol planner with a nameref-populating array-based planner, makes `--rm` a planner input, and applies the review's style/minor fixes while preserving all external Phase 1 behaviour.

## Overview

- `lib/common.sh` (new) - `die()` helper printing `talkbox: <message>` to stderr and exiting with the given code; sourced by `talkbox.sh` before the other libs and by `lib/options.sh`.
- `lib/containers.sh` - `plan_onbox <out_array_name> <project> <command> <interactive> <rm>` now appends the full `podman run` argument list to a caller-declared array via `local -n` instead of `printf`-per-line; the global `defaults/dotfiles` mount is now conditional on the directory's existence (matching the project-dotfiles pattern). `run_onbox` is a thin executor: it declares a local array, calls `plan_onbox` with `rm=yes`, and runs `podman run "${args[@]}"` with no re-parsing. Shebang removed.
- `lib/options.sh` - sources `lib/common.sh`; the unknown-option error now calls `die()`; shebang removed.
- `lib/naming.sh` - shebang removed.
- `talkbox.sh` - sources `lib/common.sh` first; the usage, not-implemented and unknown-container errors now call `die()`.
- `image/entrypoint.sh` - unchanged (the `exec bash -c "$*"` note is deferred per the plan).

## Tests edited

The edited tests and the reason for each edit:

- `test/unit/containers.bats` - rewritten from line-regex assertions to array-membership assertions. The planner contract change (text → array) forces the rewrite: the plan's Tests section states that "the existing `plan_line` / `run plan_onbox` assertions are structurally coupled to the text protocol and cannot pass against both old and new implementations", and requires replacing "the `plan_line` and `last_line` helpers with array-membership assertion helpers" where "each planner test declares a local array, calls `plan_onbox` directly (not via bats `run`...)". New coverage is added per the plan: "`--rm` is absent from the array when the `rm` parameter is `no`" and "Global dotfiles mount is absent when `$TALKBOX_ROOT/defaults/dotfiles` does not exist". This rewrite also resolves [issue: unit terminal-allocation assertion is too loose](../issues/terminal-allocation-assertion-too-loose.gen.md), which required "both an interactive flag and a tty flag in the interactive case" - the interactive test now asserts both `--interactive` and `--tty` are elements.
- `test/unit/helpers.bash` - the `load_lib` fallback message is simplified: per the plan, "remove the 'not implemented yet (see ...)' message (dead code now that all Phase 1 libs exist) and replace with a generic error indicating the lib file is absent"; the review likewise flags that "once all libs exist, the message is dead code".

## Tests unchanged

- `test/unit/options.bats` - no structural change; the unknown-option test "continues to assert exit code 2 and the `talkbox: unknown option:` message; the message now comes from `die()`".
- `test/unit/naming.bats` - no change ("pure helpers unaffected by the refactor").
- `test/e2e/*` - no new e2e tests and no edits; "all existing e2e tests must pass unchanged, confirming the refactor preserves external behaviour".

## Verification

- `make test-unit` - exit `0`; 35/35 tests passed (33 prior + 2 new planner tests).
- `make test-e2e` - exit `0`; 14/14 tests passed (unchanged).
- `make lint` - exit `0`; ShellCheck clean on all linted scripts.
- `make format` - `shfmt` clean on all modified files.
