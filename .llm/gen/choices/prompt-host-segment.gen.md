# Choice: Command-prompt host segment (`<project-slug>.<container-type>`)

#flow/redgreen

## Context

The interactive shell prompt inside `onbox`/`netbox`/`offbox` containers is defined by [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc), which is copied into `/home/dev/` by [image/entrypoint.sh](../../../image/entrypoint.sh) on every container start. The current prompt line is:

```
PS1="$dim[\t] $teal\u@\h $blue\w$reset: "
```

where `\h` is the bash hostname expansion. Phase 10b replaces the `\h` segment with the literal string `<project-slug>.<container-type>` (e.g. `my-proj.onbox`), where `<container-type>` is one of `onbox`, `netbox`, `offbox`. The `\u` segment (container user `dev`) is unchanged.

The `<project-slug>` and `<container-type>` are known on the host at plan time: `project_slug` is already defined in [lib/naming.sh](../../../lib/naming.sh), and each planner (`plan_onbox`/`plan_netbox`/`plan_offbox` in [lib/containers.sh](../../../lib/containers.sh)) knows which container type it is building. Neither value is currently available inside the container.

The prompt only matters for interactive shells (`.bashrc` is not sourced for `bash -c` noninteractive commands, which do not display a prompt), so the mechanism only needs to reach the interactive shell's environment. The established precedent for host→container value propagation is the `TALKBOX_GIT_USER_NAME`/`TALKBOX_GIT_USER_EMAIL` env-var mechanism from Phase 9b: planners append `--env` flags to the `podman create` argument list, and a dotfile/entrypoint consumer reads them. Unlike git identity, the prompt host segment is relevant for **every** container (including non-git projects), so it must not be gated on `git_mounts_enabled`.

The open design question is the shape of the value(s) passed into the container and where the `<project-slug>.<container-type>` string is assembled.

## Option A — two env vars read directly by `.bashrc` (Recommended)

Have `plan_onbox`/`plan_netbox`/`plan_offbox` each append two `--env` flags to the create-argument list, unconditionally (outside the `git_mounts_enabled` block):

- `--env TALKBOX_PROJECT_SLUG=<project_slug "$project">`
- `--env TALKBOX_CONTAINER_TYPE=<onbox|netbox|offbox>`

Then in [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) replace `\h` in the `PS1` assignment with `${TALKBOX_PROJECT_SLUG}.${TALKBOX_CONTAINER_TYPE}`. No entrypoint change is required: the env vars are in the shell environment when `.bashrc` is sourced for an interactive shell.

- Mirrors the `TALKBOX_GIT_USER_*` precedent exactly (planner emits `--env`, a dotfile consumer reads it), so all create/recontain/rebuild paths inherit the behaviour automatically through the three planners.
- The two constituent values remain individually available to project dotfiles or other in-container tools that might want the slug or container type separately.
- Survives `podman commit` inheritance: env vars are re-emitted at each container's own `podman create`, so `netbox`/`offbox` do not rely on values baked into the committed image.
- A guard (`${TALKBOX_PROJECT_SLUG:-}` / `${TALKBOX_CONTAINER_TYPE:-}`) keeps `.bashrc` from breaking when sourced outside a talkbox container (e.g. a manually started shell in the base image); the host segment simply renders empty.
- No `Containerfile` or `entrypoint.sh` change; the `.bashrc` edit is picked up on next start because dotfiles are re-copied by the entrypoint. The base image already `COPY`s `.bashrc` via the dotfiles folder bind-mount (not baked into the image), so no rebuild is required to pick up the change for new containers.

## Option B — single combined env var `TALKBOX_PROMPT_HOST`

Have the three planners append a single `--env TALKBOX_PROMPT_HOST=<slug>.<container>` flag, with the `<slug>.<container>` string assembled on the host side. `.bashrc` uses `${TALKBOX_PROMPT_HOST}` in place of `\h`.

- One env var instead of two; the prompt string assembly lives entirely on the host.
- However, the individual `<project-slug>` and `<container-type>` pieces are no longer available inside the container, so any future dotfile or tool that wants one of them would need a new mechanism. This loses reuse potential for no real gain.
- Slightly less self-documenting inside `.bashrc` (a single opaque token vs. two named pieces).

## Option C — entrypoint assembles a sourced snippet / exports a derived variable

Pass the two env vars as in Option A, but have [image/entrypoint.sh](../../../image/entrypoint.sh) assemble `TALKBOX_PROMPT_HOST=<slug>.<container>` and `export` it (or write a small sourced file under `/home/dev/`) which `.bashrc` then reads.

- Centralises the assembly in the entrypoint, so `.bashrc` stays agnostic.
- But the entrypoint already runs before the interactive shell and its exports are inherited, so this is functionally equivalent to Option A with an extra hop. It adds an entrypoint edit and a `Containerfile` rebuild requirement (the entrypoint is `COPY`ed into the image at build time) for no behavioural benefit over Option A.

## Selection

**Option A** — two env vars read directly by `.bashrc`. (Selected, per user.)
