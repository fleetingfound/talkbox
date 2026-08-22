# Phase 2: mounts, ports and onbox lifecycle management

#flow/redgreen #model/default

## Scope

Adds all mount and port logic to `onbox` (deferred from Phase 1): the read/write mount files, the port file, their CLI overrides, mount precedence ordering, and the onbox image/container lifecycle subcommands. Also transitions the normal `onbox` run from the Phase-1 ephemeral model (`podman run --rm`) to the persistent container model (`podman create` + `podman start`) required by the SPEC's lifecycle management and by Phase 3's root filesystem inheritance via `podman commit`.

### Implemented from SPEC.md

- Mount specification format: `<source>` / `<source> : <dest>`, blank/`#` lines ignored, `~`/`$HOME` placeholder expansion in `<source>`, `~`/`$HOME`/`$PROJECT` in `<dest>`, default dest `/host/read/<basename>` / `/host/write/<basename>`.
- `defaults/read.mounts` and `defaults/write.mounts` parsing (files may be empty/absent).
- `--read` and `--write` arguments (repeatable, same input format as the mount files) combined with the global defaults (union of all mounts).
- `defaults/ports` parsing (one port per line, blank/`#` ignored, file may be empty/absent).
- `--port` argument (repeatable) combined with the global `defaults/ports` (union).
- Mount precedence: when identical or nested `<dest>` paths are provided, mount shallower-to-deeper so deeper paths' permissions win; deduplicate identical dests.
- `pasta` `-T,<port>` host-port forwarding per port for `onbox`.
- `onbox --recontain` (recreate container and associated volumes, then start).
- `onbox --rebuild` (rebuild base image, recreate container, start).
- `onbox --rm-container` (remove container and associated volumes).
- `onbox --rm-image` (remove base image unless used by other containers).
- Persistent container model: the normal `onbox` run creates a named, persistent container (`podman create` then `podman start`) rather than an ephemeral `podman run --rm` container. `onbox -c <command>` runs the command within the existing container (creating it first if it does not exist). The container persists after the shell/command exits until `--rm-container` is invoked. Container names follow the `<project-slug>.onbox` convention so lifecycle verbs can identify them. This is required by §image and container management and by §filesystem inheritance (Phase 3).

### Deferred

- `netbox`/`offbox` and their lifecycle analogues (Phase 3).
- Root filesystem inheritance and `--fresh`/`--inherit` (Phase 3).
- Git mounts and gitdir volume (Phase 4).

## External-facing functionality

- `onbox` (no flags) creates a named, persistent container if one does not yet exist and starts an interactive shell; the container persists after the shell exits. `onbox -c <command>` runs the command within the existing container (creating it first if needed).
- `onbox --read <spec> [--read <spec> ...]`, `onbox --write <spec> [--write <spec> ...]`, `onbox --port <n> [--port <n> ...]`.
- `onbox --recontain`, `onbox --rebuild`, `onbox --rm-container`, `onbox --rm-image`.
- Default mounts and ports from `defaults/` are now applied (in addition to the Phase-1 core mounts).

## Files to create / modify

- Create `lib/mounts.sh` - parse a mount file into source/dest pairs; expand `~`/`$HOME`/`$PROJECT`; default-dest derivation; merge default-file mounts with CLI `--read`/`--write` mounts into a single depth-sorted, deduplicated list per (read/write) mode; emit per-mount `podman` `-v` argument strings.
- Create `lib/ports.sh` - parse `defaults/ports`; merge with `--port` values; emit the deduplicated, ordered `pasta` `-T` port list.
- Modify `lib/naming.sh` - add container name derivation (`<project-slug>.onbox`) so lifecycle verbs can identify the persistent container.
- Modify `lib/options.sh` - parse the new repeatable `--read`/`--write`/`--port` flags and the lifecycle verbs; expose them in the structured record alongside the Phase-1 command/interactive fields.
- Modify `lib/containers.sh` - integrate the `lib/mounts.sh` and `lib/ports.sh` output into the onbox argument-list planner (replacing the hardcoded extra-mount slots while keeping the worktree + dotfiles core mounts); transition the normal `onbox` run from `podman run --rm` to a persistent create-if-not-exists + start model (with `onbox -c <command>` exec'ing into the existing container); implement `--recontain`, `--rebuild`, `--rm-container`, `--rm-image` with pure plan assembly separate from the `podman`-executing wrappers.
- Modify `talkbox.sh` - route the lifecycle verbs to the new actions.

## Files to read during implementation

- `SPEC.md` (mount specification format, mount precedence, read-only/read-write mounts, network, image and container management, command execution).
- `defaults/read.mounts`, `defaults/write.mounts`, `defaults/ports`.
- `.llm/gen/choices/test-modularization.gen.md`.
- Phase-1 `lib/*.sh`, `talkbox.sh`, `image/entrypoint.sh`.

## Key internal interfaces

- `lib/naming.sh`: a pure function returning the onbox container name (`<project-slug>.onbox`) for a given project path, alongside the existing base/volume name helpers.
- `lib/mounts.sh`: a function that, given a mount file path and a read/write mode plus a list of CLI specs, returns the depth-ordered, deduplicated `podman` `-v` flag list. Placeholder expansion honours an injected project-base / project path / home value so it is unit-testable without a real project. Depth = number of path segments in `<dest>`; identical dest collapses to one entry (last wins for the same mode); nested-but-distinct dests are ordered shallow-to-deep so deeper permissions override.
- `lib/ports.sh`: a function returning the ordered, deduplicated port list for a container from the defaults file plus CLI `--port` values.
- `lib/options.sh`: the parser returns a structured record of selected verb, command/interactive mode, read/write/port lists.
- `lib/containers.sh`: a planner function returning the sequence of `podman` invocations for the normal run (create-if-not-exists + start, or exec for `-c` commands) and for each lifecycle verb (so the plan is unit-testable); an executor runs them. The normal run no longer includes `--rm`; the Phase-1 `rm` planner parameter is retired in favour of the persistent model.

## Tests

- **Unit tests** (`test/unit/`): sourcing `lib/mounts.sh` and asserting on mount-file parsing (both line forms, `#`/blank lines, missing file, default dest, placeholder expansion for `~`/`$HOME`/`$PROJECT`), depth-ordered dedup (identical dest collapses with deeper permission winning; nested dests ordered shallow-to-deep; cross-mode independence), union of default-file and CLI mounts; sourcing `lib/ports.sh` and asserting on port-file parsing (missing/empty/dedup) and union with `--port`; sourcing `lib/naming.sh` and asserting on container name derivation; sourcing `lib/containers.sh` and asserting on the onbox assembled `podman` argument list now including default mounts and `-T` ports (and no longer including `--rm` for the normal run), and on lifecycle plan assembly (which `podman` subcommands and in what order for each verb, `--rm-image` in-use guard logic). The Phase-1b test asserting `--rm` presence is updated to reflect the persistent model.
- **End-to-end tests** (`test/e2e/`): `onbox` creates a persistent container that survives after the shell exits; `onbox -c <command>` execs into the existing container; `onbox --read`/`--write`/`--port` produce a container where the extra mount is visible/writable and the extra port is reachable; `onbox --rm-container` leaves no container/volumes; `onbox --recontain` recreates and starts; `onbox --rebuild` rebuilds the image and starts. E2e test teardown must clean up persistent containers. Run under the existing `systemd-run`-wrapped runner.
