# Phase 1: onbox minimal working application

#flow/redgreen #model/default

## Scope

Implements the smallest externally-usable slice of `SPEC.md`: the `onbox` command creating a container from the shared base image with internet access and direct edits to the host working tree, dotfiles applied on entry, and an interactive shell by default (plus `-c`/`--command` execution).

All mount-file parsing, port-file parsing, CLI mount/port overrides, mount precedence ordering and lifecycle verbs are deferred to Phase 2. Phase 1 hardcodes the onbox core mounts (host worktree read-write bind-mount and the two dotfiles bind-mounts) and uses basic `pasta` networking for internet access without `-T` host-port forwarding.

### Implemented from SPEC.md

- `onbox` container definition (shared base image; host worktree bind-mounted read-write to `/working/<project-base>/`; global + project dotfiles bind-mounted read-only).
- User mapping `--userns=keep-id:uid=1000,gid=1000`.
- Network: rootless `pasta` with `--cap-drop=NET_ADMIN --cap-drop=NET_RAW`, internet allowed (host-port `-T` forwarding deferred to Phase 2).
- Interactive shell default with `/working/<project-base>/` as working directory; `-c`/`--command <command>` with `--interactive` (default) / `--noninteractive`.
- `entrypoint.sh` copies global then project dotfiles into `/home/dev/` (project overrides global).
- Naming: `<project-base>`, `<project-slug>`, base image name.
- Dispatcher: `talkbox.sh onbox` and symlinked invocation as `onbox`.

### Deferred

- Read/write mount files and `--read`/`--write` arguments (Phase 2).
- Port file and `--port` argument, `pasta` `-T` host-port forwarding (Phase 2).
- Mount depth-ordering / nested-dest precedence (Phase 2).
- `--recontain`/`--rebuild`/`--rm-container`/`--rm-image` (Phase 2).
- Git mounts, gitdir volume, `/host/git` remote, submodule absorption (Phase 4).
- `netbox` and `offbox` containers (Phase 3).
- Root filesystem inheritance, `--fresh`/`--inherit` (Phase 3).
- Git transport subcommands (Phase 4 fetch, Phase 5 merge/sync).

## External-facing functionality

- `talkbox.sh onbox` (and `onbox` symlink) starts an interactive shell in a container at `/working/<project-base>/` with internet, the host worktree writable, and dotfiles installed.
- `onbox -c <command>`, `onbox -c --interactive <command>`, `onbox -c --noninteractive <command>`.
- Base image built on first run (delegates to `podman build` using `image/Containerfile`).

## Files to create

- `talkbox.sh` - dispatcher: resolve invocation name or first positional arg (`onbox`/`netbox`/`offbox`); for this phase only `onbox` is routed. Sources `lib/*.sh` as needed, then calls the onbox action. Executable.
- `lib/naming.sh` - pure helpers for `<project-base>`, `<project-slug>`, base image name.
- `lib/options.sh` - argument parsing for the `-c`/`--command`/`--interactive`/`--noninteractive` flags used by `onbox` (structured to be extended in later phases).
- `lib/containers.sh` - base image build, onbox container create/start, interactive shell vs. command execution. Pure assembly of the `podman` argument list (image, workdir, userns, network flags, the hardcoded worktree + dotfiles `-v` flags, entrypoint/command) is factored into a planner function so unit tests can assert on it; a thin executor actually runs `podman`.
- `image/entrypoint.sh` - in-container entrypoint: apply global dotfiles from `/talkbox/dotfiles.global/`, then project dotfiles from `/talkbox/dotfiles.project/` over them into `/home/dev/`; then `exec` the user command or shell. The file is referenced by `Containerfile` (which already `COPY`s it) but is currently absent and must be created.

## Files to read during implementation

- `SPEC.md` (naming, onbox, network, dotfiles, user mapping, command execution, implementation).
- `image/Containerfile` (already references `entrypoint.sh`).
- `test/runner.mk`, `test/run-suite.sh`, `test/lib.bash` (existing harness conventions).
- `.llm/gen/choices/module-structure.gen.md`, `.llm/gen/choices/test-modularization.gen.md`.
- `.llm/ref/podman.docs`, `.llm/ref/passt.docs`.

## Key internal interfaces

- Dispatcher: invoke as `talkbox.sh <container>` or via symlink; first positional selects container; remaining positionals and flags forwarded to the container action.
- `lib/naming.sh`: pure functions returning the project base name, slug, and base image name given a project path.
- `lib/options.sh`: a parser returning a structured record of the selected command/interactive mode for `onbox`.
- `lib/containers.sh`: a planner function returning the full `podman run`/`podman create` argument list for `onbox` (image, workdir `/working/<project-base>/`, userns, network flags, worktree bind-mount, dotfiles bind-mounts, entrypoint/command) so unit tests can assert on the assembled command; a thin executor runs `podman`.
- `image/entrypoint.sh`: idempotent dotfile copy (project overrides global) followed by `exec "$@"` / `exec bash`.

## Tests

- **Unit tests** (`test/unit/`): sourcing `lib/naming.sh` and `lib/options.sh` and asserting on slug/base-name generation and `-c`/`--interactive`/`--noninteractive` parsing; sourcing `lib/containers.sh` and asserting on the assembled onbox `podman` argument list (workdir, userns, network flags, worktree bind-mount path, dotfiles bind-mount paths).
- **End-to-end tests** (`test/e2e/`): invoke `talkbox.sh onbox -c --noninteractive` against a temporary git repo, asserting: container starts, working directory is `/working/<project-base>/`, writing a file inside the container appears on the host worktree, internet access works (e.g. a bounded `curl`/`wget` to a known host), and dotfiles from a fake `defaults/dotfiles/` are present in `/home/dev/`. At least one `expect`-driven interactive test that starts `onbox` and exits via `exit`.

All podman-invoking tests run under the existing `systemd-run`-wrapped runner.
