# Phase 1a: Planner truthfulness — project-dotfiles existence in plan_onbox

#flow/redgreen #model/default

## Scope

Resolves review item 8 (planner-vs-executor dotfiles-existence split) per [Choice: planner-vs-executor project-dotfiles existence handling](../choices/planner-dotfiles-existence.gen.md) (Option A). The existence check for `$project/.dotfiles` moves from the executor `run_onbox` into the planner `plan_onbox`, so that the planner's output is the exact `podman` argument list `podman run` receives. `run_onbox` becomes a thin pass-through executor with no filtering.

This is the first phase of the test-suite revision and is implemented before [Phase 1b](phase-1b-test-suite-revision.gen.md) so that the `containers.bats` planner tests in Phase 1b operate against the truthful planner.

### Implemented from SPEC.md

- [SPEC.md §onbox](../../../SPEC.md): "the project dotfiles folder `<project>/.dotfiles/`, bind-mounted to `/talkbox/dotfiles.project/` when it exists on the host (read-only bind-mount)" — the existence condition now lives where the mount line is emitted, making the planner output truthful.

### Deferred

- All test-suite coverage-gap and correctness fixes (terminal-allocation assertion, timeout mismatch, unknown-option, dispatcher, `--rm`, `base_image_name`, `--command`/`-c --interactive` e2e, read-only mount verification, network skip) — deferred to [Phase 1b](phase-1b-test-suite-revision.gen.md).

## External-facing functionality

None externally observable. `onbox` behaviour is unchanged: when `<project>/.dotfiles` exists it is mounted read-only; when it does not, it is omitted. Only the internal placement of the existence check changes. Existing e2e tests (which exercise both the present and absent cases) must continue to pass unchanged.

## Files to create

None.

## Files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — `plan_onbox` (emitter) and `run_onbox` (filtering executor).
- [test/unit/containers.bats](../../../test/unit/containers.bats) — `onbox plan bind-mounts project dotfiles read-only` and the existing planner tests, which call `plan_onbox '/tmp/talkbox-proj' ...` against a path without `.dotfiles`.
- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats) — `project dotfiles override global dotfiles in /home/dev` (creates `$PROJECT/.dotfiles`) and the other e2e tests (do not create `.dotfiles`).
- [Choice: planner-vs-executor project-dotfiles existence handling](../choices/planner-dotfiles-existence.gen.md).
- [Review: Phase 1 onbox test suite](../reviews/phase-1-onbox-test-suite.gen.md) (item 8).

## Key internal interfaces to be modified

- [lib/containers.sh](../../../lib/containers.sh) `plan_onbox`: emit the `-v <project>/.dotfiles:/talkbox/dotfiles.project:ro` line only when `$project/.dotfiles` is a directory. This gives `plan_onbox` a filesystem dependency; callers that previously relied on the line always being present must be aware.
- [lib/containers.sh](../../../lib/containers.sh) `run_onbox`: remove the special-case filtering of the project-dotfiles `-v` line. The executor becomes a straight pass-through that splits each `-v <src>:<dst>:<mode>` line into `-v` and its argument and otherwise appends lines verbatim, then runs `podman run`.

## Tests

- **Unit tests** (`test/unit/containers.bats`): the existing `onbox plan bind-mounts project dotfiles read-only` test must be updated so its setup creates `$project/.dotfiles` (e.g. a temp project directory) before calling `plan_onbox`, so the line is emitted and the assertion remains truthful. Add a complementary unit test asserting that when `$project/.dotfiles` does not exist, `plan_onbox` output contains no `dotfiles.project` line. The existing planner tests that call `plan_onbox` with a bare `/tmp/talkbox-proj` path and do not create `.dotfiles` must be reconciled (either give them a real temp project, or assert the dotfiles line's absence where appropriate) so they remain truthful under the new planner semantics.
- **End-to-end tests** (`test/e2e/onbox.bats`): no new e2e test required; the existing `project dotfiles override global dotfiles in /home/dev` test (which creates `.dotfiles`) and the other e2e tests (which do not) already exercise both branches and must continue to pass unchanged, confirming the implementation change preserves behaviour.

Verification: `make test-unit` and `make test-e2e` both pass after the implementation change.
