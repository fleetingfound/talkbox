# Phase 4: git integration (onbox/netbox/offbox) and fetch

#flow/redgreen #model/default

## Scope

Adds the git-specific mounts and in-container wiring to all three containers (`onbox`, `netbox`, `offbox`): the per-container gitdir volume, the read-only host git folder, the `host` remote, worktree configuration, submodule absorption on the host, and refusal to mount when the host git directory lies outside `<project>`. Also implements the `fetch` git-transport subcommand, which moves committed changes from a container's gitdir volume into the host repository via a git bundle.

### Implemented from SPEC.md

- Git mounts for all three containers: host `<project>/.git/` bind-mounted read-only to `/host/git/`; volume `<project-slug>.<container>.gitdir` mounted read-write to `/working/<project-base>/.git/`.
- After creating/mounting the gitdir volume, set `/host/git/` as a remote and `/working/<project-base>/` as its working tree (inside the container, via `entrypoint.sh`).
- Refuse to mount when the host git directory of `<project>/` lies outside `<project>/`.
- Submodule absorption: submodules are absorbed into the host top-level git directory before being included; git operations inside a submodule are prevented within the container (must be made on the host).
- Behaviour when `<project>/` is not tracked by git: the commands still work; the git-related mounts/wiring are simply unavailable.
- Git may be used to make in-container changes visible/auditable from the host and as transport for syncing committed changes.
- `fetch`: `onbox fetch` / `netbox fetch` / `offbox fetch` fetch changes from the corresponding `<project-slug>.<container>.gitdir` via a git bundle; `fetch --all` fetches from the onbox, netbox and offbox git histories. Bundles are the only transport for git history from container to host (configs/hooks not transferred).

### Deferred

- `custom_merge()` and the `merge`/`sync` subcommands (Phase 5).

## External-facing functionality

- `onbox`, `netbox`, `offbox` (no flags) on a git-tracked `<project>` produce a container whose `/working/<project-base>/` is a working tree backed by a per-container gitdir volume, with the host git history available as the `host` remote.
- The same commands on a non-git `<project>` behave as in earlier phases (no git mounts/wiring).
- The same commands on a git `<project>` whose `.git` resolves outside `<project>/` exit with an error explaining the refusal.
- `onbox|netbox|offbox fetch [--all]` brings committed changes from the container's gitdir volume into the host repository via a bundle.

## Files to create / modify

- Create `lib/git.sh` - host-side git helpers: detect whether `<project>` is git-tracked; resolve the host git directory and determine whether it lies outside `<project>`; list submodule git dirs for absorption; bundle creation/extraction helpers; the `fetch` action (create a bundle from a container's gitdir volume history for the relevant refs and fetch it into the host repo). (`custom_merge()` and merge/sync are added here in Phase 5.)
- Modify `lib/containers.sh` - conditionally add the git mounts (host git folder read-only bind-mount to `/host/git/`; per-container gitdir volume read-write to `/working/<project-base>/.git/`) when the project is git-tracked and the git directory is inside `<project>`, for all three containers; create and populate the gitdir volume using the no-network volume-population helper from Phase 3 (copying from `/host/git/` when the volume is empty). Pure mount-planning is factored so the git-mount decision and the resulting `-v` flags are unit-testable.
- Modify `lib/options.sh` - parse the `fetch` subcommand verb and its `--all` flag.
- Modify `image/entrypoint.sh` - after dotfile application, if the gitdir volume is mounted, configure the `host` remote pointing at `/host/git/` and set `/working/<project-base>/` as the working tree; enforce that git operations inside submodules are blocked (e.g. by making submodule `.git` entries non-writable or detecting submodule context and erroring).
- Modify `talkbox.sh` - wire the refusal check before container creation for all three containers; route the `fetch` subcommand for each container.

## Files to read during implementation

- `SPEC.md` (mounts gitdir/host-git sections for onbox/netbox/offbox, git as transport, fetch).
- `.llm/gen/choices/volume-population.gen.md`.
- Phase-1/2/3 `lib/*.sh`, `talkbox.sh`, `image/entrypoint.sh`.
- `.llm/ref/podman.docs` (for any `podman exec`/temporary-container execution used to create bundles from a gitdir volume).

## Key internal interfaces

- `lib/git.sh`:
  - Pure helpers to (a) detect git-tracked status, (b) resolve and classify the host git directory (inside vs. outside `<project>`), (c) list submodule git dirs for absorption. These are unit-testable against fixture paths without running `git`.
  - Bundle helpers - create a bundle from a container's gitdir volume history for the relevant refs, and fetch from that bundle into the host repo; thin wrappers over `git bundle`.
  - A `fetch` action function composing the above; the bundle is created by running git against the gitdir volume (via a temporary container mounting the volume, or `podman exec` into the container, with no network needed).
- `lib/containers.sh`: a predicate deciding whether to emit git mounts for a given project; the existing argument-assemblers gain an optional git-mounts segment appended when the predicate is true.
- `lib/options.sh`: the `fetch` verb and `--all` flag are exposed in the parsed record.
- `image/entrypoint.sh`: a guarded remote/worktree configuration step that is a no-op when the gitdir volume is absent, plus submodule-git-blocking enforcement.

## Tests

- **Unit tests** (`test/unit/`): sourcing `lib/git.sh` and asserting on inside/outside classification of resolved git directories (using fixture paths), git-tracked detection, submodule-dir listing; sourcing `lib/containers.sh` and asserting the onbox/netbox/offbox assembled `podman` argument lists include git mounts when applicable and exclude them when not; the fetch action plan assembly (which git subcommands run and against which gitdir volume).
- **End-to-end tests** (`test/e2e/`): `onbox`/`netbox`/`offbox` on a temporary git repo shows the `host` remote inside the container and a commit made in-container is visible in the gitdir volume; the same commands on a non-git folder work without git mounts; `onbox`/`netbox`/`offbox` on a project whose `.git` is a gitdir file pointing outside `<project>/` refuses with a clear error; a submodule's git operations are blocked inside the container; `onbox fetch` (and `--all`) brings a container commit into the host repo via a bundle without transferring configs/hooks. Run under the existing `systemd-run`-wrapped runner.
