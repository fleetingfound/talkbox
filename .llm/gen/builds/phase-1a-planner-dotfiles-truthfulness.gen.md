# Phase 1a: Planner truthfulness — project-dotfiles existence in plan_onbox

Status: `SUCCESS`

This build implements [phase-1a-planner-dotfiles-truthfulness.gen.md](../plans/phase-1a-planner-dotfiles-truthfulness.gen.md), which moves the `<project>/.dotfiles` existence check from the executor into the planner so that `plan_onbox`'s output is the exact argument list `podman run` receives.

## Overview

- `lib/containers.sh::plan_onbox` now emits the `-v <project>/.dotfiles:/talkbox/dotfiles.project:ro` line only when `<project>/.dotfiles` is a directory.
- `lib/containers.sh::run_onbox` is now a thin pass-through executor: it splits each `-v <src>:<dst>:<mode>` line into `-v` and its argument and appends all other lines verbatim, with the project-dotfiles filtering special case removed.
- No test files were edited; the phase-1a unit tests (present and absent branches) already existed in the red state and now pass.

## Verification

- `make test-unit` - exit `0`; 30/30 tests passed.
- `make test-e2e` - exit `0`; 10/10 tests passed.

## Notes

- This build is the first phase of the test-suite revision, implemented before Phase 1b so the Phase 1b `containers.bats` planner tests operate against the truthful planner.
- No dispute or issue documents were produced; the existing issues from [phase-1-onbox-test-suite.gen.md](../reviews/phase-1-onbox-test-suite.gen.md) are deferred to Phase 1b per the plan's Deferred section.
