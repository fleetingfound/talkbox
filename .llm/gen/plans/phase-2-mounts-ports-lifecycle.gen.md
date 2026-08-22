# Phase 2: mounts, ports and onbox lifecycle management

#flow/redgreen #model/default

## Scope

Adds all mount and port logic to `onbox` (deferred from Phase 1): the read/write mount files, the port file, their CLI overrides, mount precedence ordering, and the onbox image/container lifecycle subcommands.

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

### Deferred

- `netbox`/`offbox` and their lifecycle analogues (Phase 3).
- Root filesystem inheritance and `--fresh`/`--inherit` (Phase 3).
- Git mounts and gitdir volume (Phase 4).

## External-facing functionality

- `onbox --read <spec> [--read <spec> ...]`, `onbox --write <spec> [--write <spec> ...]`, `onbox --port <n> [--port <n> ...]`.
- `onbox --recontain`, `onbox --rebuild`, `onbox --rm-container`, `onbox --rm-image`.
- Default mounts and ports from `defaults/` are now applied (in addition to the Phase-1 core mounts).

## Files to create / modify

- Create `lib/mounts.sh` - parse a mount file into source/dest pairs; expand `~`/`$HOME`/`$PROJECT`; default-dest derivation; merge default-file mounts with CLI `--read`/`--write` mounts into a single depth-sorted, deduplicated list per (read/write) mode; emit per-mount `podman` `-v` argument strings.
- Create `lib/ports.sh` - parse `defaults/ports`; merge with `--port` values; emit the deduplicated, ordered `pasta` `-T` port list.
- Modify `lib/options.sh` - parse the new repeatable `--read`/`--write`/`--port` flags and the lifecycle verbs; expose them in the structured record alongside the Phase-1 command/interactive fields.
- Modify `lib/containers.sh` - integrate the `lib/mounts.sh` and `lib/ports.sh` output into the onbox argument-list planner (replacing the hardcoded extra-mount slots while keeping the worktree + dotfiles core mounts); implement `--recontain`, `--rebuild`, `--rm-container`, `--rm-image` with pure plan assembly separate from the `podman`-executing wrappers.
- Modify `talkbox.sh` - route the lifecycle verbs to the new actions.

## Files to read during implementation

- `SPEC.md` (mount specification format, mount precedence, read-only/read-write mounts, network, image and container management).
- `defaults/read.mounts`, `defaults/write.mounts`, `defaults/ports`.
- `.llm/gen/choices/test-modularization.gen.md`.
- Phase-1 `lib/*.sh`, `talkbox.sh`, `image/entrypoint.sh`.

## Key internal interfaces

- `lib/mounts.sh`: a function that, given a mount file path and a read/write mode plus a list of CLI specs, returns the depth-ordered, deduplicated `podman` `-v` flag list. Placeholder expansion honours an injected project-base / project path / home value so it is unit-testable without a real project. Depth = number of path segments in `<dest>`; identical dest collapses to one entry (last wins for the same mode); nested-but-distinct dests are ordered shallow-to-deep so deeper permissions override.
- `lib/ports.sh`: a function returning the ordered, deduplicated port list for a container from the defaults file plus CLI `--port` values.
- `lib/options.sh`: the parser returns a structured record of selected verb, command/interactive mode, read/write/port lists.
- `lib/containers.sh`: a planner function returning the sequence of `podman` invocations for each lifecycle verb (so the plan is unit-testable); an executor runs them.

## Tests

- **Unit tests** (`test/unit/`): sourcing `lib/mounts.sh` and asserting on mount-file parsing (both line forms, `#`/blank lines, missing file, default dest, placeholder expansion for `~`/`$HOME`/`$PROJECT`), depth-ordered dedup (identical dest collapses with deeper permission winning; nested dests ordered shallow-to-deep; cross-mode independence), union of default-file and CLI mounts; sourcing `lib/ports.sh` and asserting on port-file parsing (missing/empty/dedup) and union with `--port`; sourcing `lib/containers.sh` and asserting on the onbox assembled `podman` argument list now including default mounts and `-T` ports, and on lifecycle plan assembly (which `podman` subcommands and in what order for each verb, `--rm-image` in-use guard logic).
- **End-to-end tests** (`test/e2e/`): `onbox --read`/`--write`/`--port` produce a container where the extra mount is visible/writable and the extra port is reachable; `onbox --rm-container` leaves no container/volumes; `onbox --recontain` recreates and starts; `onbox --rebuild` rebuilds the image and starts. Run under the existing `systemd-run`-wrapped runner.
