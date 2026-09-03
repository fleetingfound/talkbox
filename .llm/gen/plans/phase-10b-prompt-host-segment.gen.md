# Plan: Phase 10b — Command-prompt host segment (`<project-slug>.<container-type>`)

#flow/redgreen #model/default

## Specification scope

This phase is not specified verbatim in [SPEC.md](../../../SPEC.md) but is a follow-on to the **dotfiles** section (lines 192-201) and the **naming conventions** section (lines 30-34). It changes the interactive shell prompt inside `onbox`/`netbox`/`offbox` containers so that the host segment shows the literal string `<project-slug>.<container-type>` (e.g. `my-proj.onbox`) instead of the bash hostname expansion `\h`. The `\u` segment (container user `dev`) is unchanged.

The design follows [Command-prompt host segment](../choices/prompt-host-segment.gen.md) — Option A: the three planners append two `--env` flags (`TALKBOX_PROJECT_SLUG` / `TALKBOX_CONTAINER_TYPE`) to the `podman create` argument list, and [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) reads them when assembling `PS1`.

No other aspect of `SPEC.md` / `SPEC.gen.md` is altered. (There is no `SPEC.gen.md`.)

## To be implemented

- In [lib/containers.sh](../../../lib/containers.sh), inside `plan_onbox`, `plan_netbox` and `plan_offbox`, append two unconditional `--env` flags to the create-argument list (placed among the other top-level `podman create` flags, e.g. right after the GPU block and before the `-v` mount list, mirroring the placement of the GPU options in Phase 7):
  - `--env TALKBOX_PROJECT_SLUG=<project_slug "$project">`
  - `--env TALKBOX_CONTAINER_TYPE=<onbox|netbox|offbox>` (each planner emits its own literal container type)
- In [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc), replace the `\h` token in the `PS1` assignment with `${TALKBOX_PROJECT_SLUG}.${TALKBOX_CONTAINER_TYPE}`. Use the `:-` default-expansion form (`${TALKBOX_PROJECT_SLUG:-}` / `${TALKBOX_CONTAINER_TYPE:-}`) so that `.bashrc` does not break under `set -u` and renders an empty host segment when sourced outside a talkbox container (e.g. a manually started shell in the base image).
- No changes to [lib/options.sh](../../../lib/options.sh): these are container-runtime env vars passed to `podman create`, not host-side parsed options, exactly like `TALKBOX_GIT_USER_NAME`/`TALKBOX_GIT_USER_EMAIL` in Phase 9b. They are not gated on `git_mounts_enabled` because the prompt is relevant for every container, including non-git projects.
- No changes to [image/entrypoint.sh](../../../image/entrypoint.sh) or [image/Containerfile](../../../image/Containerfile): the env vars are already in the interactive shell's environment when `.bashrc` is sourced, and the dotfiles are re-copied by the entrypoint on every start. The base image does not bake `.bashrc` in (it is bind-mounted from `defaults/dotfiles/`), so no image rebuild is required to pick up the `.bashrc` edit for new containers.

Because the three planners are the single source of truth for create arguments, the default-create (`run_onbox`/`run_netbox`/`run_offbox`), recontain and rebuild paths all inherit the prompt host segment automatically, exactly as GPU support (Phase 7) did. Because the env vars are re-emitted at each container's own `podman create`, `netbox`/`offbox` inheritance via `podman commit` is handled correctly (committed images do not preserve runtime `-e` vars, but each container re-passes its own).

## To be deferred

- A mechanism to override or disable the prompt host segment (e.g. a `--no-prompt-host` flag). Not requested; the `<project-slug>.<container-type>` segment always applies.
- Customisation of the prompt beyond the host segment (colours, layout, the `\u`/`\t`/`\w` segments). Out of scope; only `\h` is replaced.
- Propagation into the temporary no-network helper containers used by `plan_volume_populate` and the `container_sync_cmd` fallback `podman run`. These perform only file copies or git fetch/merge operations non-interactively and never display a prompt, so they have no need for the env vars.
- Making `<project-slug>`/`<container-type>` available to project dotfiles in any form other than these two env vars. The env vars already expose them to any dotfile or in-container tool that wants them.

## External-facing functionality

When `onbox`, `netbox` or `offbox` start an interactive shell in a container, the prompt's host segment shows `<project-slug>.<container-type>` (e.g. `dev@my-proj.onbox`) instead of the container's hostname. The behaviour is identical across all three container types and applies whether or not the project is git-tracked. Noninteractive `-c` commands are unaffected (no prompt is displayed).

## Files to be created

- None.

## Files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — `plan_onbox`, `plan_netbox`, `plan_offbox`: append the two `--env` flags among the top-level create flags.
- [lib/naming.sh](../../../lib/naming.sh) — `project_slug` is reused unchanged to compute the slug value.
- [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) — replace `\h` in the `PS1` assignment with the `${TALKBOX_PROJECT_SLUG}.${TALKBOX_CONTAINER_TYPE}` expansion.
- [image/entrypoint.sh](../../../image/entrypoint.sh) — confirm no entrypoint change is required (the env vars reach the interactive shell directly).
- [image/Containerfile](../../../image/Containerfile) — confirm no image change is required (`.bashrc` is bind-mounted from `defaults/dotfiles/`, not baked in).
- [talkbox.sh](../../../talkbox.sh) — confirm no dispatcher changes are required (the planners consume `project_slug` directly).

## Key internal interfaces

- `TALKBOX_PROJECT_SLUG` — environment variable passed to `podman create` by the three planners and consumed by `.bashrc`. Container-runtime env var, distinct from the host-side option globals (`TALKBOX_GPU`, `TALKBOX_FRESH`, etc.); not parsed by `lib/options.sh`.
- `TALKBOX_CONTAINER_TYPE` — environment variable passed to `podman create` by the three planners, taking the literal value `onbox`, `netbox` or `offbox` depending on which planner emits it. Consumed by `.bashrc`.
- `project_slug` (in [lib/naming.sh](../../../lib/naming.sh)) — reused unchanged as the source of the slug value.

## Tests

Requires tests, unit only.

- **Unit tests:**
  - The three planners each emit `--env TALKBOX_PROJECT_SLUG=<slug>` and `--env TALKBOX_CONTAINER_TYPE=<container>` tokens inside the create-argument list, with the correct per-planner container type and the correct slug derived from the project. These can be asserted against the nameref-populated plan array without invoking `podman`, mirroring the existing planner unit tests in `test/unit/containers.bats` and `test/unit/netbox-offbox.bats` (alongside the `--name=<slug>.<container>` assertions already present).
  - The env vars are emitted unconditionally (i.e. present for a non-git project where `git_mounts_enabled` is false), distinguishing this behaviour from the `TALKBOX_GIT_USER_*` tokens which are gated on `git_mounts_enabled`.
  - The recontain and rebuild plan paths inherit the env vars (one assertion per planner is sufficient, mirroring the Phase 7 GPU recontain/rebuild assertions).
