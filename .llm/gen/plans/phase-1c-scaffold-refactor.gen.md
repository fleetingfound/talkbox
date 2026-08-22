# Phase 1c: Scaffold refactor — array-based planner and style fixes

#flow/unified #model/default

## Scope

Addresses the highest-value recommendation from [Review: Phase 1 onbox implementation as a scaffold](../reviews/phase-1-onbox-scaffold.gen.md): replacing the fragile text-protocol planner with a nameref-populating array-based planner (recommendation 1), making `--rm` a planner input rather than a constant (recommendation 8), and applying the style/minor fixes the review identifies. The scope is deliberately minimal — other scaffold recommendations (lifecycle executor seams, shared-base split, stub mounts/ports, generalized options parser, image-operations seam) are deferred to their natural phases where concrete requirements validate them.

Per [Choice: scaffold-refactor-scope](../choices/scaffold-refactor-scope.gen.md) (Option C selected) and [Choice: Planner array-population mechanism](../choices/planner-array-mechanism.gen.md) (Option A — nameref selected).

This phase preserves all external Phase 1 behaviour. No new user-facing functionality is added; `onbox` continues to start an interactive shell or run a command exactly as before.

### Implemented from SPEC.md

No new SPEC.md aspects are implemented. The phase refactors the internal structure of the Phase 1 implementation while preserving its behaviour:

- [SPEC.md §onbox](../../../SPEC.md) — the global dotfiles mount is bind-mounted from `defaults/dotfiles/`; the refactor makes this mount conditional on the directory's existence (matching the project-dotfiles pattern already in place), which is a robustness improvement, not a behaviour change for the shipped repo.
- [SPEC.md §image and container management](../../../SPEC.md) (implicit) — `--rm` semantics: the container is removed after exit. The refactor makes `--rm` a planner input so that future lifecycle verbs (Phase 2) can opt out, but Phase 1 always passes `yes`.

### Deferred

- **Rec 2** (lifecycle-aware executor with image/container/volume seams) — Phase 2, where `--recontain`/`--rebuild`/`--rm-*` provide concrete requirements.
- **Rec 3** (shared base + container-specific overrides) — Phase 3, where `netbox` validates the split.
- **Rec 4** (stub `lib/mounts.sh` and `lib/ports.sh`) — Phase 2, where mount/port parsing is actually implemented.
- **Rec 5** (generalized `options.sh` with structured record and list-valued fields) — Phase 2, where repeatable `--read`/`--write`/`--port` provide concrete pressure.
- **Rec 7** (`root_image_name()` and `lib/images.sh`) — Phase 3, where `podman commit` and `--rm-image` in-use detection are implemented.

## External-facing functionality

None. `onbox` behaviour is unchanged: interactive shell, `-c`/`--command` with `--interactive`/`--noninteractive`, dotfiles applied, worktree writable, internet access. Existing e2e tests must pass unchanged.

## Files to create

- `lib/common.sh` — a small shared utilities module containing the `die()` helper (prints `talkbox: <message>` to stderr and exits with the given code). Sourced by `talkbox.sh` before other libs and by `lib/options.sh` and `lib/containers.sh` as needed, so that unit tests sourcing a single lib get `die()` transitively.

## Files to modify

- `lib/containers.sh`:
  - `plan_onbox`: change from `printf`-per-line to a nameref-populating function. The first argument is the name of a caller-declared array; the function appends the full `podman run` argument list to it via `local -n`. The signature gains a fifth parameter (`rm`: `yes`/`no`) controlling whether `--rm` is appended. Filesystem existence checks (project `.dotfiles`, and now also global `defaults/dotfiles`) remain inline at emit time per recommendation 6 — the planner's output is the truthful `podman` argument list.
  - `run_onbox`: becomes a thin executor. Declares a local array, calls `plan_onbox` with `rm=yes`, and runs `podman run "${args[@]}"`. All re-parsing and `-v` special-casing is removed.
  - Remove the `#!/usr/bin/env bash` shebang (the file is always sourced, never executed).
- `lib/options.sh`:
  - Source `lib/common.sh` so `die()` is available when the lib is sourced in isolation by unit tests.
  - Replace the inline `printf 'talkbox: unknown option: %s\n'` + `return 2` with a call to `die()`.
  - Remove the shebang.
- `lib/naming.sh`:
  - Remove the shebang.
- `talkbox.sh`:
  - Source `lib/common.sh` before the other libs.
  - Replace the inline error messages (usage, unknown container, not-implemented) with `die()` calls.
- `image/entrypoint.sh`:
  - No change for this phase. The review's note about `exec bash -c "$*"` vs `exec "$@"` is explicitly "minor, given the SPEC's single-string contract" and is not a clear improvement for Phase 1; deferred.
- `test/unit/helpers.bash`:
  - Simplify the `load_lib` fallback: remove the "not implemented yet (see ...)" message (dead code now that all Phase 1 libs exist) and replace with a generic error indicating the lib file is absent.

## Files to read during implementation

- [SPEC.md](../../../SPEC.md) (§onbox, §image and container management, §dotfiles).
- [lib/containers.sh](../../../lib/containers.sh) — current `plan_onbox` (text emitter) and `run_onbox` (re-parsing executor).
- [lib/options.sh](../../../lib/options.sh), [lib/naming.sh](../../../lib/naming.sh) — current lib structure and shebangs.
- [talkbox.sh](../../../talkbox.sh) — current error messages and source order.
- [test/unit/containers.bats](../../../test/unit/containers.bats) — `plan_line`/`last_line` helpers and line-regex assertions coupled to the text protocol.
- [test/unit/options.bats](../../../test/unit/options.bats), [test/unit/naming.bats](../../../test/unit/naming.bats), [test/unit/helpers.bash](../../../test/unit/helpers.bash) — existing unit-test style.
- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats), [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — e2e tests that must pass unchanged (external behaviour preserved).
- [Review: Phase 1 onbox implementation as a scaffold](../reviews/phase-1-onbox-scaffold.gen.md) (recommendations 1, 6, 8; style issues).
- [Choice: scaffold-refactor-scope](../choices/scaffold-refactor-scope.gen.md), [Choice: Planner array-population mechanism](../choices/planner-array-mechanism.gen.md).

## Key internal interfaces

- `lib/common.sh` `die()`: takes a message and an exit code; prints `talkbox: <message>` to stderr and exits with the code. Used by `talkbox.sh` and `lib/options.sh`.
- `lib/containers.sh` `plan_onbox <out_array_name> <project> <command> <interactive> <rm>`: appends the complete `podman run` argument list to the caller-declared array named by the first argument, using `local -n`. The `rm` parameter (`yes`/`no`) controls whether `--rm` is included. Filesystem existence checks for `$project/.dotfiles` and `$TALKBOX_ROOT/defaults/dotfiles` are performed inline at emit time; the corresponding `-v` lines are omitted when the directories are absent. The function produces no stdout.
- `lib/containers.sh` `run_onbox <project> <command> <interactive>`: declares a local array, calls `plan_onbox` with `rm=yes`, and executes `podman run "${array[@]}"`. No re-parsing, no line-reading, no `-v` special-casing.
- `lib/options.sh` sources `lib/common.sh` so `die()` is available when sourced in isolation.

## Tests

This phase uses `#flow/unified` because the planner contract change (text → array) forces the unit tests to be rewritten alongside the implementation — the existing `plan_line` / `run plan_onbox` assertions are structurally coupled to the text protocol and cannot pass against both old and new implementations.

### Unit tests (`test/unit/`)

- **`containers.bats`** — rewrite all planner tests:
  - Replace the `plan_line` and `last_line` helpers with array-membership assertion helpers (e.g. a function that checks whether a given string appears as an element of the array).
  - Each planner test declares a local array, calls `plan_onbox` directly (not via bats `run`, since the function populates an array by nameref and produces no stdout), and asserts on array membership and ordering.
  - Existing coverage to preserve: workdir, userns, network (`pasta`, no `-T`), cap-drops, worktree bind-mount (read-write), global dotfiles mount (read-only), project dotfiles mount (present when `.dotfiles` exists, absent otherwise), base image name, `--rm` presence, interactive (`--interactive` + `--tty`), noninteractive (no terminal flags), command appended as last element.
  - New coverage: `--rm` is absent from the array when the `rm` parameter is `no` (the planner input controls `--rm`). Global dotfiles mount is absent when `$TALKBOX_ROOT/defaults/dotfiles` does not exist (override `TALKBOX_ROOT` to a temp dir in the test setup).
- **`options.bats`** — the unknown-option test continues to assert exit code 2 and the `talkbox: unknown option:` message; the message now comes from `die()`. No structural change to these tests beyond confirming `lib/common.sh` is sourced transitively when `options.sh` is loaded.
- **`naming.bats`** — no change (pure helpers unaffected by the refactor).

### End-to-end tests (`test/e2e/`)

- No new e2e tests. All existing e2e tests must pass unchanged, confirming the refactor preserves external behaviour. The `run_onbox_noninteractive` helper and the `expect`-driven interactive test exercise the full `talkbox.sh onbox` → `run_onbox` → `podman run` path end-to-end.

### Verification

- `make test-unit` — all unit tests pass with the rewritten array-based planner assertions.
- `make test-e2e` — all e2e tests pass unchanged, confirming external behaviour is preserved.
- `make lint` — ShellCheck passes (no new warnings from the nameref usage; the `local -n` may require a shellcheck directive if it flags the nameref variable as unused).
- `make format` — `shfmt` passes on all modified files.
