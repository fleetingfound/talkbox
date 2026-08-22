# Tests: Phase 1a planner truthfulness — project-dotfiles existence in plan_onbox

Linked plan: [phase-1a-planner-dotfiles-truthfulness.gen.md](../plans/phase-1a-planner-dotfiles-truthfulness.gen.md)

Summary: this phase moves the `<project>/.dotfiles` existence check from the executor `run_onbox` into the planner `plan_onbox` (per [Choice: planner-vs-executor project-dotfiles existence handling](../choices/planner-dotfiles-existence.gen.md), Option A) so that `plan_onbox`'s output is the truthful `podman` argument list `podman run` receives, with `run_onbox` becoming a thin pass-through executor.

## New tests

- `test/unit/containers.bats` - `onbox plan omits the project dotfiles bind-mount when .dotfiles is absent` - calls `plan_onbox` against a real temporary project directory that has no `.dotfiles` folder and asserts the output contains no `dotfiles.project` line. This test fails before the plan is implemented because the current `plan_onbox` unconditionally emits `-v <project>/.dotfiles:/talkbox/dotfiles.project:ro` (it fails with `[[ "$output" != *'dotfiles.project'* ]]`), and will pass once `plan_onbox` consults the filesystem and omits the line when `$project/.dotfiles` is not a directory. The new test is observed to fail with `make test-unit` (1 fail / 29 pass) for exactly this reason.

## Tests edited

- `test/unit/containers.bats` - `onbox plan bind-mounts project dotfiles read-only when they exist` (renamed from `onbox plan bind-mounts project dotfiles read-only`) - the test body now creates `$PROJECT/.dotfiles` before calling `plan_onbox`, so the `-v <project>/.dotfiles:/talkbox/dotfiles.project:ro` line is emitted and the read-only assertion remains truthful.
  - Evidence from the plan: "the existing `onbox plan bind-mounts project dotfiles read-only` test must be updated so its setup creates `$project/.dotfiles` (e.g. a temp project directory) before calling `plan_onbox`, so the line is emitted and the assertion remains truthful."
- `test/unit/containers.bats` - all remaining planner tests (`onbox plan sets the working directory to /working/<project-base>`, `onbox plan maps the host user to container uid/gid 1000`, `onbox plan uses rootless pasta networking without host-port forwarding`, `onbox plan drops NET_ADMIN and NET_RAW capabilities`, `onbox plan bind-mounts the host worktree read-write`, `onbox plan bind-mounts global dotfiles read-only`, `onbox plan runs the shared base image`, `onbox interactive plan allocates a terminal`, `onbox noninteractive plan does not allocate a terminal`, `onbox noninteractive plan appends the command`) - these previously called `plan_onbox '/tmp/talkbox-proj' ...` against a non-existent path; a `setup()` now creates a real temporary project directory `$PROJECT="$BATS_TEST_TMPDIR/talkbox-proj"` and the tests call `plan_onbox "$PROJECT" ...`, keeping them truthful once `plan_onbox` gains its filesystem dependency.
  - Evidence from the plan: "The existing planner tests that call `plan_onbox` with a bare `/tmp/talkbox-proj` path and do not create `.dotfiles` must be reconciled (either give them a real temp project, or assert the dotfiles line's absence where appropriate) so they remain truthful under the new planner semantics." and "This gives `plan_onbox` a filesystem dependency; callers that previously relied on the line always being present must be aware."

## Tests removed

None. No pre-existing tests were inconsistent with the plan document, `SPEC.md` or `SPEC.gen.md` in a way that required removal; the planner tests were reconciled in place as described above, and the existing end-to-end tests in `test/e2e/onbox.bats` (which exercise both the present and absent `.dotfiles` branches) are left unchanged and continue to pass (`make test-e2e`: 10/10 pass), as required by the plan's External-facing functionality section: "Existing e2e tests (which exercise both the present and absent cases) must continue to pass unchanged."
