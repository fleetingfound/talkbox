# Choice: ASCII art display location

#flow/unified

## Context

The three container commands `onbox`, `netbox` and `offbox` should display distinct ASCII art when a container is started. The art must support ANSI SGR sequences (e.g. `\033[0;34m`) for colours and must be distinct per container type.

The container type is already known on the host (each `run_*` executor is container-specific) and inside the container (the `TALKBOX_CONTAINER_TYPE` env var, set by the three planners). The `run_onbox`/`run_netbox`/`run_offbox` executors in [lib/containers.sh](../../../lib/containers.sh) are the single point at which an interactive shell is launched via `podman exec --interactive --tty "$ctr" /bin/bash`, and they already receive the `interactive` flag and the `command` string. The `.bashrc` at [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) is sourced only for interactive shells (not for `bash -c` noninteractive commands), and is re-copied into `/home/dev/` by [image/setup.sh](../../../image/setup.sh) on every container start.

The open question is whether the art is printed by the host-side executor (before entering the container) or from inside the container (by `.bashrc` or a sourced script).

## Option A — host-side executor prints art before `podman exec` (Recommended)

Add a helper function (in a new `lib/banner.sh` or inline in `lib/containers.sh`) that reads the appropriate art file from `$TALKBOX_ROOT` and prints it to the host terminal immediately before the `podman exec --interactive --tty` call in `run_onbox`/`run_netbox`/`run_offbox`. The print is gated on `interactive == yes` and `command` being empty (the bare interactive shell start), so noninteractive `-c` commands and recontain/rebuild paths show no art.

- Art files stay in the repo and are read directly from `$TALKBOX_ROOT`; no bind-mount, no image change, no `.bashrc` change.
- The art appears exactly once, before the shell prompt — the typical "banner on startup" pattern. It does not reappear for subshells started inside the container.
- The executor already knows the container type and the interactive flag, so the gating logic is trivial.
- No coupling to the dotfiles copy mechanism or the image build; adding or editing art takes effect immediately without a rebuild.

## Option B — `.bashrc` prints art from bind-mounted files

Bind-mount an art directory from the repo into the container (read-only, alongside the existing `setup.sh` bind-mount), and have `.bashrc` `cat` or `printf` the art for the current `TALKBOX_CONTAINER_TYPE` when sourced. Since `.bashrc` is only sourced for interactive shells, noninteractive `-c` commands are naturally excluded.

- Integrates the art into the shell session itself, appearing after `.bashrc` is sourced.
- However, `.bashrc` is re-sourced for every interactive subshell (`bash` typed at the prompt, `tmux` new panes), so the art would repeat unless an additional guard is added (e.g. a sentinel variable).
- Requires a new bind-mount in all three planners and a `.bashrc` edit, increasing the surface area.
- The art directory would need to be mounted in the temporary no-network helper containers used by `container_sync_cmd` fallback, or guarded against its absence — extra conditionals for no behavioural gain.

## Option C — bake art files into the base image

`COPY` the art files into the image in [image/Containerfile](../../../image/Containerfile) and have `.bashrc` read them from a fixed path inside the container.

- Art is always present in the image, no bind-mount needed.
- But editing art requires an image rebuild (`--rebuild`), which is heavyweight for a cosmetic change.
- Inherits the `.bashrc` subshell-repeat problem from Option B.
- The art would be baked into the shared base image, which is shared across all projects — acceptable, but inflexible.

## Selection

**Option B** — `.bashrc` prints art from bind-mounted files. (Selected, per user.)

The subshell-repeat concern is addressed by an exported sentinel variable set after the first display, so child shells inherit it and skip the banner. The new bind-mount is guarded on directory existence (as the `defaults/dotfiles` mount already is), and the `.bashrc` block degrades gracefully when the art file is absent, so temporary no-network helper containers (which do not source `.bashrc` anyway) are unaffected.
