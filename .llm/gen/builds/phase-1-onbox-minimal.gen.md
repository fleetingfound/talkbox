# Phase 1: onbox minimal working application

Status: `SUCCESS`

This build implements [phase-1-onbox-minimal.gen.md](../plans/phase-1-onbox-minimal.gen.md), the smallest externally-usable slice of `SPEC.md`.

## Overview

- `talkbox.sh` dispatches `onbox` (via `talkbox.sh onbox` or an `onbox` symlink) and rejects the not-yet-implemented `netbox`/`offbox`.
- `lib/naming.sh` provides pure `project_base`, `project_slug` and `base_image_name` helpers.
- `lib/options.sh` parses `-c`/`--command`, `--interactive` and `--noninteractive`, recording `ONBOX_COMMAND` and `ONBOX_INTERACTIVE`.
- `lib/containers.sh` plans the onbox `podman run` argument list (`plan_onbox`: workdir `/working/<project-base>/`, `--userns=keep-id:uid=1000,gid=1000`, `--network=pasta` without host-port forwarding, `--cap-drop=NET_ADMIN`/`NET_RAW`, read-write worktree bind-mount, read-only global/project dotfiles bind-mounts, terminal flags for interactive runs, base image and appended command), builds the shared base image on first run (`ensure_base_image`) and executes `podman` (`run_onbox`), skipping the project-dotfiles mount when `<project>/.dotfiles` does not exist.
- `image/entrypoint.sh` copies global then project dotfiles into `/home/dev/` (project overrides global) and executes the user command via `bash -c`, falling back to an interactive shell.

## Verification

- `make test-unit` - exit `0`; 29/29 tests passed.
- `make test-e2e` - exit `0`; 10/10 tests passed.

## Notes

- Podman, `pasta` (passt) and `uidmap` were installed in the environment to run the end-to-end suite.
- No dispute or issue documents were produced.
