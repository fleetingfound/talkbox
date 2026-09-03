# Build: Phase 10b — Command-prompt host segment (`<project-slug>.<container-type>`)

Status: **SUCCESS**

Implemented [Phase 10b](.llm/gen/plans/phase-10b-prompt-host-segment.gen.md): the three persistent-container planners `plan_onbox`, `plan_netbox` and `plan_offbox` in [lib/containers.sh](../../../lib/containers.sh) now unconditionally append `--env TALKBOX_PROJECT_SLUG=<project_slug "$project">` and `--env TALKBOX_CONTAINER_TYPE=<onbox|netbox|offbox>` among the top-level `podman create` flags (right after the GPU block, before the `-v` mount list), and [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) replaces the `\h` token in its `PS1` assignment with `${TALKBOX_PROJECT_SLUG:-}.${TALKBOX_CONTAINER_TYPE:-}` so the interactive prompt shows `<project-slug>.<container-type>` (e.g. `dev@my-proj.onbox`) while remaining safe under `set -u` when sourced outside a talkbox container. No entrypoint, image, options or test-harness changes were required, per the selected design in [Command-prompt host segment](.llm/gen/choices/prompt-host-segment.gen.md) (Option A).

Verified: `make test-unit` passes 205/205; `make test-e2e` passes 67/67.
