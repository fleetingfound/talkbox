# Plan: Phase 17a — ASCII art banner on container startup

#flow/unified #model/default

## Specification scope

This phase is not specified in [SPEC.md](../../../SPEC.md) or `SPEC.gen.md` (which does not exist). It adds a new cosmetic feature: distinct ASCII art displayed when an interactive `onbox`, `netbox` or `offbox` shell is started. The art supports ANSI SGR colour sequences (e.g. `\033[0;34m`).

The design follows two choices:

- [ASCII art display location](../choices/ascii-art-display-location.gen.md) — Option B: `.bashrc` prints art from bind-mounted files inside the container.
- [ASCII art file format and storage](../choices/ascii-art-file-format.gen.md) — Option A: `defaults/art/` with `\033` notation interpreted by `printf '%b'`.

No other aspect of `SPEC.md` is altered.

## To be implemented

- Create a `defaults/art/` directory containing three distinct ASCII art files: `onbox.txt`, `netbox.txt` and `offbox.txt`. Each file contains ASCII art with ANSI SGR colour sequences written in `\033` octal notation (e.g. `\033[0;34m...`). Each file ends with a `\033[0m` reset sequence so no colour state leaks into the shell. The art is distinct per container type and visually identifies the container type (e.g. the container name rendered as figlet-style ASCII art with colours).
- In [lib/containers.sh](../../../lib/containers.sh), inside `plan_onbox`, `plan_netbox` and `plan_offbox`, add a conditional read-only bind-mount of `$TALKBOX_ROOT/defaults/art` to `/talkbox/art:ro`, placed alongside the existing `defaults/dotfiles` bind-mount block and guarded on directory existence in the same way (i.e. only added when `$TALKBOX_ROOT/defaults/art` exists as a directory). This mount applies to all three container types unconditionally (not gated on `git_mounts_enabled`), because the banner is relevant for every container.
- In [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc), add a banner block (near the top, before the `PS1` assignment) that:
  - Checks an exported sentinel variable (e.g. `_TALKBOX_BANNER_SHOWN`); if already set, skips the banner so that subshells (`bash` typed at the prompt, child processes) do not repeat the art. The sentinel is exported so child shells inherit it.
  - Checks that `TALKBOX_CONTAINER_TYPE` is set and non-empty and that the corresponding art file exists at `/talkbox/art/${TALKBOX_CONTAINER_TYPE}.txt`; if either condition fails, the block is a no-op (graceful degradation when `.bashrc` is sourced outside a talkbox container, or in a container where the art mount is absent).
  - Reads the art file content and passes it through `printf '%b'` so that `\033` escape sequences are interpreted into raw ESC bytes for the terminal. A trailing newline is emitted after the art.
  - Sets and exports the sentinel variable after printing.
- No changes to [image/setup.sh](../../../image/setup.sh): the art directory is bind-mounted at `/talkbox/art/` and read directly by `.bashrc`; it is not copied into `/home/dev/`. The `.bashrc` copy in `/home/dev/` (copied from `defaults/dotfiles/` by `setup.sh`) reads from the bind-mounted art path.
- No changes to [image/Containerfile](../../../image/Containerfile): the art is not baked into the image; it is bind-mounted at container creation time by the three planners.
- No changes to [lib/options.sh](../../../lib/options.sh) or [talkbox.sh](../../../talkbox.sh): the banner is driven entirely by the existing `TALKBOX_CONTAINER_TYPE` env var and the new bind-mount; no new CLI options are introduced.

Because the three planners are the single source of truth for create arguments, the default-create (`run_onbox`/`run_netbox`/`run_offbox`), recontain and rebuild paths all inherit the art bind-mount automatically. Because `.bashrc` is only sourced for interactive non-login shells, noninteractive `-c` commands do not display the banner. The sentinel prevents repetition in interactive subshells.

## To be deferred

- Project-level art override (e.g. `<project>/.art/` overriding `defaults/art/`). Not requested; the repo-provided art always applies.
- A `--no-banner` CLI flag to suppress the art. Not requested.
- Customisation of the art content by the user at runtime. The art files are repo assets; editing them requires a repo change.
- Propagation of the art bind-mount into the temporary no-network helper containers used by `plan_volume_populate` and the `container_sync_cmd` fallback `podman run`. These never source `.bashrc` (they run `cp` or `bash -c` noninteractively), so the mount is unnecessary.
- A `tmux`-aware sentinel that suppresses the banner across tmux panes (tmux new panes may not inherit the parent shell's exported sentinel). Acceptable edge case; deferred.

## External-facing functionality

When `onbox`, `netbox` or `offbox` is invoked without `-c` (the default interactive shell), the terminal displays distinct coloured ASCII art identifying the container type before the first shell prompt. The art is different for each of the three container types. Noninteractive invocations (`-c --noninteractive` or `-c --interactive <command>`) do not display the art, because `.bashrc` is not sourced. The art does not repeat when the user starts a subshell inside the container.

## Files to be created

- `defaults/art/onbox.txt` — ASCII art with `\033` SGR colour sequences for the `onbox` container.
- `defaults/art/netbox.txt` — ASCII art with `\033` SGR colour sequences for the `netbox` container.
- `defaults/art/offbox.txt` — ASCII art with `\033` SGR colour sequences for the `offbox` container.

## Files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — `plan_onbox`, `plan_netbox`, `plan_offbox`: add the `defaults/art` bind-mount alongside the existing `defaults/dotfiles` mount block.
- [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) — add the banner block (sentinel check, art file read, `printf '%b'` output) before the `PS1` assignment.
- [image/setup.sh](../../../image/setup.sh) — confirm no change is required (`.bashrc` is copied to `/home/dev/`; art is read from the bind-mounted `/talkbox/art/`).
- [image/Containerfile](../../../image/Containerfile) — confirm no image change is required.
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — `mk_talkbox` copies `defaults/` recursively, so `defaults/art/` is automatically available in e2e; confirm no helper change is needed.

## Key internal interfaces

- `TALKBOX_CONTAINER_TYPE` — existing env var (set by the three planners to `onbox`, `netbox` or `offbox`), consumed by the new `.bashrc` banner block to select the art file. No change to its definition.
- `/talkbox/art/` — new read-only bind-mount target inside the container, populated from `$TALKBOX_ROOT/defaults/art/`. Contains `<container-type>.txt` files. Added by the three planners.
- `_TALKBOX_BANNER_SHOWN` — new exported shell variable set by `.bashrc` after the banner is printed. Child shells inherit it and skip the banner. Not an env var passed to `podman create`; it exists only within the container's shell environment.
