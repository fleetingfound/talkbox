# Phase 3: netbox and offbox containers

#flow/redgreen #model/default

## Scope

Implements the `netbox` and `offbox` containers, their volume-based mounts, root filesystem inheritance via `podman commit`, the no-network volume-population helper, and the `--fresh`/`--inherit` options, plus the network isolation for `offbox`.

Git mounts (gitdir volumes and `/host/git`) are deferred to Phase 4, where they are added to all three containers uniformly. In this phase `netbox`/`offbox` carry the worktree volume, dotfiles mounts, read mounts (read-only bind-mounts) and write mounts (read-write volumes) only.

### Implemented from SPEC.md

- `netbox` container: root image = `podman commit` of `onbox` if it exists, else shared base image; worktree volume `<project-slug>.netbox.worktree` (populated from host working tree); write mounts as read-write volumes (copied from host source, named `<project-slug>.netbox.write.<dest-slug>`); read mounts as read-only bind-mounts; global + project dotfiles bind-mounted read-only as in onbox; never has host write access.
- `offbox` container: root image = `podman commit` of `netbox` if it exists, else of `onbox`, else shared base image; worktree volume `<project-slug>.offbox.worktree` (copied from `netbox` worktree volume if it exists, else from host); write-mount volumes copied from the corresponding `netbox` write volume if it exists, else from host source (named `<project-slug>.offbox.write.<dest-slug>`); read mounts and dotfiles as in onbox.
- `<dest-slug>` derivation (`<dest>` converted to a hyphenated alphanumeric slug).
- Root filesystem inheritance rules (onbox<-base, netbox<-onbox, offbox<-netbox<-onbox<-base).
- `--fresh` prevents default inheritance of the root filesystem and read-write volumes.
- `--inherit <onbox|netbox|offbox>` selects the explicit inheritance source for root fs and read-write volumes.
- `offbox` network: `pasta:-T,<port1>,-T,<port2>,-i,lo,-I,talkbox0` plus `--cap-drop=NET_ADMIN --cap-drop=NET_RAW` (internet blocked).
- `netbox`/`offbox` lifecycle analogues of `--recontain`/`--rebuild`/`--rm-container`/`--rm-image` (with root image recreation on recontain/rebuild and root image removal on rm-container).
- No-network temporary helper container for volume population, with the host source mounted read-only (per the chosen volume-population strategy).

### Deferred

- Git mounts, gitdir volumes, `/host/git` remote/worktree wiring, submodule absorption (Phase 4).
- Git transport subcommands (Phase 4 fetch, Phase 5 merge/sync).

## External-facing functionality

- `netbox` and `offbox` (and `talkbox.sh netbox`/`talkbox.sh offbox`) with the same `-c`/`--command`/`--interactive`/`--noninteractive`, `--read`/`--write`/`--port`, `--recontain`/`--rebuild`/`--rm-container`/`--rm-image` surface as `onbox`, plus `--fresh`/`--inherit`.
- `netbox` has internet and no host write access; `offbox` has no internet and no host write access.
- Edits inside `netbox`/`offbox` affect volumes, never the host working tree.

## Files to create / modify

- Modify `lib/naming.sh` - emit netbox/offbox volume and root-image names; `<dest-slug>` derivation.
- Modify `lib/options.sh` - parse `--fresh` and `--inherit <source>`.
- Modify `lib/mounts.sh` - support emitting volume-mount flags (not just bind-mounts) for write mounts under netbox/offbox, while read mounts remain read-only bind-mounts.
- Modify `lib/containers.sh` - implement: root-image inheritance planner (`podman commit` source selection given existence state and `--fresh`/`--inherit`); the no-network helper-container volume populator (mounts host source read-only or a source volume, target volume read-write, `--network=none`, copies the tree); netbox/offbox create/start; lifecycle verbs for netbox/offbox (including root image recreation/removal).
- Modify `talkbox.sh` - route `netbox`/`offbox`.

## Files to read during implementation

- `SPEC.md` (mounts read-write volumes, netbox, offbox, filesystem inheritance, inheritance options, network, image and container management, implementation note on temporary containers).
- `.llm/gen/choices/volume-population.gen.md`.
- Phase-1/2 `lib/*.sh`, `talkbox.sh`, `image/entrypoint.sh`.

## Key internal interfaces

- `lib/naming.sh`: pure functions returning netbox/offbox volume names, root-image names, and `<dest-slug>` for a given dest path.
- `lib/mounts.sh`: a mode parameter selects bind-mount (onbox) vs. volume-mount (netbox/offbox) emission for write mounts.
- `lib/options.sh`: the inheritance selection is exposed alongside the other parsed flags.
- `lib/containers.sh`:
  - An inheritance planner: given the current existence of onbox/netbox/offbox containers and the `--fresh`/`--inherit` selection, returns the root-image source (a container to commit, or `base`). Pure and unit-testable.
  - A volume-population planner: given a target volume, a source kind (`host` | `volume`), the source path/volume, and the chosen inheritance, returns the `podman run --rm --network=none ...` argument list for the helper container (asserting read-only host source and `--network=none`). Pure; an executor runs `podman`.
  - Argument-list assemblers for netbox and offbox mirroring the onbox assembler (worktree volume, read-only bind-mounts for reads, read-write volumes for writes, dotfiles bind-mounts, correct pasta flags incl. offbox's `-i,lo,-I,talkbox0`).

## Tests

- **Unit tests** (`test/unit/`): `<dest-slug>` derivation; inheritance planner for all combinations of existing containers and `--fresh`/`--inherit` (including base-image fallback when no source container exists); volume-population planner argument lists for host-source and volume-source cases (asserting `--network=none` and read-only host source mount); netbox/offbox `podman` argument-list assembly (volume mounts for writes, read-only bind-mounts for reads, correct pasta flags incl. offbox's `-i,lo,-I,talkbox0`); lifecycle plan assembly for netbox/offbox including root-image commit/removal.
- **End-to-end tests** (`test/e2e/`): `netbox` container has internet, edits land in the worktree volume (not the host), and inherits `onbox` root when onbox exists; `offbox` container has no internet (a bounded network probe fails) and no host write; `offbox` created after `netbox` copies the netbox worktree/write volumes; `--fresh` ignores existing containers/volumes and copies from host; `--inherit` selects the specified source; `netbox --rm-container`/`--rm-image` remove the root image; `netbox --rebuild` commits onbox and recreates. Run under the existing `systemd-run`-wrapped runner.
