# Tests: Phase 10b — Command-prompt host segment (`<project-slug>.<container-type>`)

Linked plan: [phase-10b-prompt-host-segment.gen.md](../plans/phase-10b-prompt-host-segment.gen.md)

Summary: this phase adds red-green unit tests for the plan's two changes — the three persistent-container planners `plan_onbox`/`plan_netbox`/`plan_offbox` appending two unconditional `--env` flags (`TALKBOX_PROJECT_SLUG`/`TALKBOX_CONTAINER_TYPE`) to the `podman create` argument list, and `defaults/dotfiles/.bashrc` replacing the `\h` hostname token in the `PS1` assignment with `${TALKBOX_PROJECT_SLUG:-}.${TALKBOX_CONTAINER_TYPE:-}` so the interactive prompt's host segment shows `<project-slug>.<container-type>` (e.g. `dev@my-proj.onbox`) — per [Choice: Command-prompt host segment](../choices/prompt-host-segment.gen.md) (Option A), following the **naming conventions** section of [SPEC.md](../../../SPEC.md) (lines 30-34) and the **dotfiles** section (lines 192-201).

## New tests

Unit tests (per the plan's Test section: "The three planners each emit `--env TALKBOX_PROJECT_SLUG=<slug>` and `--env TALKBOX_CONTAINER_TYPE=<container>` tokens inside the create-argument list, with the correct per-planner container type and the correct slug derived from the project"; "The env vars are emitted unconditionally (i.e. present for a non-git project where `git_mounts_enabled` is false), distinguishing this behaviour from the `TALKBOX_GIT_USER_*` tokens which are gated on `git_mounts_enabled`"; "The recontain and rebuild plan paths inherit the env vars (one assertion per planner is sufficient, mirroring the Phase 7 GPU recontain/rebuild assertions)"):

- `test/unit/containers.bats` — two `plan_onbox` tests:
  - `onbox plan emits the prompt host env vars for git-tracked and non-git projects` — for a git-tracked project (host identity configured) asserts the create-argument array contains `TALKBOX_PROJECT_SLUG=talkbox-proj` and `TALKBOX_CONTAINER_TYPE=onbox` alongside the git-identity tokens, and for a non-git folder asserts the same two tokens (slug `plain`) while `TALKBOX_GIT_USER` remains absent — covering the correct slug/container-type emission and the unconditional (non-git) case in one test.
  - `onbox recontain and rebuild plans propagate the prompt host env vars to podman create` — asserts both `plan_recontain` and `plan_rebuild` (which embed the `plan_onbox` create args) contain the two tokens.
- `test/unit/netbox-offbox.bats` — four tests:
  - `netbox plan emits the prompt host env vars for git-tracked and non-git projects` and the analogous `offbox` test — the same assertions through `plan_netbox`/`plan_offbox` with container types `netbox`/`offbox`.
  - `netbox recontain and rebuild plans propagate the prompt host env vars to podman create` and the analogous `offbox` test — assert both the `*_recontain` and `*_rebuild` plans of each planner carry the tokens (one assertion per planner, as the plan allows).
- `test/unit/bashrc.bats` (new file) — `bashrc replaces the hostname in PS1 with the talkbox project slug and container type` — sources `defaults/dotfiles/.bashrc` in a fresh `bash --noprofile --norc` with `TALKBOX_PROJECT_SLUG=my-proj`/`TALKBOX_CONTAINER_TYPE=onbox` exported and asserts the resulting `PS1` contains `@my-proj.onbox` and no longer contains the `\h` token (the plan's implementation bullet: "replace the `\h` token in the `PS1` assignment with `${TALKBOX_PROJECT_SLUG:-}.${TALKBOX_CONTAINER_TYPE:-}`").

Against the current (unimplemented) code all 7 unit tests fail for the correct reason: the three planners emit no `TALKBOX_PROJECT_SLUG`/`TALKBOX_CONTAINER_TYPE` tokens, so `array_contains` fails, and the sourced `.bashrc` still assigns `PS1` with the literal `\h` hostname token, so the `@my-proj.onbox` substring is absent — none of which is a test-implementation error or timeout. The full e2e suite (67 tests) continues to pass unchanged, since the plan requires unit tests only and the interactive e2e tests never assert prompt content.

## Tests edited

- None. No existing test assertion needed modification: the e2e interactive tests (`onbox starts an interactive shell that exits via exit`, `onbox -c --interactive runs a command and the session exits via exit`) drive the session through `expect` and match on a sentinel marker echoed by the user, never on prompt content, so the `PS1` change cannot affect them; and no unit test inspects the prompt or the `.bashrc` file.

## Tests removed

- None. No pre-existing test is inconsistent with the plan: the plan only adds two unconditional `--env` flags to the three planners and replaces the `\h` token in `.bashrc`'s `PS1`, changing no existing behaviour ("No other aspect of `SPEC.md` / `SPEC.gen.md` is altered"), and no existing test asserts an exact full argument list, the absence of `--env` flags, or the prompt string.
