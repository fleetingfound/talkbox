# Phase 2: mounts, ports and onbox lifecycle management

Status: `SUCCESS`

This build implements [phase-2-mounts-ports-lifecycle.gen.md](../plans/phase-2-mounts-ports-lifecycle.gen.md), which adds the read/write mount files, the ports file and their `--read`/`--write`/`--port` CLI overrides with mount-precedence ordering, the `--recontain`/`--rebuild`/`--rm-container`/`--rm-image` lifecycle verbs, and transitions the normal `onbox` run from the ephemeral `podman run --rm` model to the persistent named-container model.

No verdict document was provided for this phase, and no new dispute or issue documents were created.

## Overview

- `lib/mounts.sh` (new) - `mount_args <out> <mode> <defaults_file> <project> <home> [cli_spec ...]` parses mount-file lines and CLI specs (`<source>` or `<source> : <dest>`, skipping blank/`#` lines), expands `~`/`$HOME` (source and dest) and `$PROJECT` (dest), derives default dests `/host/read/<basename>` / `/host/write/<basename>`, collapses identical dests (last source wins) and orders nested dests shallow-to-deep, emitting the merged `-v` list (`:ro` for read mode).
- `lib/ports.sh` (new) - `port_args <out> <defaults_file> [cli_port ...]` parses the ports file (skipping blank/`#` lines) and merges CLI `--port` values into a deduplicated, ordered `-T,<port>` token list.
- `lib/naming.sh` - adds `onbox_container_name <project>` returning `<project-slug>.onbox` so lifecycle verbs can identify the persistent container.
- `lib/options.sh` - parses the repeatable `--read`/`--write`/`--port` flags and the lifecycle verbs into the structured record (`ONBOX_READ`, `ONBOX_WRITE`, `ONBOX_PORT` arrays, `ONBOX_VERB`).
- `lib/containers.sh` - `plan_onbox` builds the `podman create` args for the persistent container (`--name=<slug>.onbox`, workdir, userns, `pasta` network with `-T` ports, cap-drops, worktree + dotfiles core mounts, merged read/write mounts, `-it` when interactive, base image, and a `sleep infinity` main process so the container stays alive for `podman exec`); `plan_onbox_run`, `plan_recontain`, `plan_rebuild`, `plan_rm_container` and `plan_rm_image` assemble the podman subcommand sequences; `execute_plan` runs them and the `run_*` executors implement the persistent model (create-if-not-exists, start, exec, and stop at the end of each session so the detached container's `conmon` does not keep the `systemd-run` harness cgroup alive), plus the lifecycle verbs.
- `talkbox.sh` - routes the lifecycle verbs to the new actions and assembles the mount/port argument lists from the `defaults/` files plus CLI values before running.

## Verification

- `make test-unit` - exit `0`; 70/70 tests passed.
- `make test-e2e` - exit `0`; 22/22 tests passed.
- `make lint` - exit `0`; ShellCheck clean on all modified scripts.
- `make format` - `shfmt` clean on all modified scripts.
