# Phase 8a: Lifecycle verbs remove and recreate named volumes

#flow/redgreen #model/default

## aspect of specification

Implements the "associated volumes" requirements of [SPEC.md](../../../SPEC.md) for the image and container management verbs:

- `--rm-container` "removes the container, together with associated volumes".
- `--recontain` "recreates the container and **all of its associated volumes** and then starts the container".
- `--rebuild` "rebuilds the base image and recreates the container and then starts the container" (recreation includes the associated volumes, by analogy with `--recontain`).

Resolves the open issue [lifecycle-verbs-leave-named-volumes-orphaned](../issues/lifecycle-verbs-leave-named-volumes-orphaned.gen.md).

Nothing else in `SPEC.md` is deferred by this phase; it is a targeted fix to the lifecycle verbs.

## external-facing functionality

After this phase:

- `onbox --rm-container` removes the `onbox` container and its gitdir named volume (`<slug>.onbox.gitdir`).
- `netbox --rm-container` removes the `netbox` container, its root image, its worktree volume, its gitdir volume, and each of its write volumes (`<slug>.netbox.write.<dest-slug>`).
- `offbox --rm-container` removes the `offbox` container, its root image, its worktree volume, its gitdir volume, and each of its write volumes (`<slug>.offbox.write.<dest-slug>`).
- `--recontain` and `--rebuild` for all three containers remove the associated named volumes before the populate/gitdir-volume steps run, so that the worktree, write and gitdir volumes are recreated cleanly rather than merged into stale content. A freshly recontained container no longer shows the previous container's git history or stale worktree/write content.

Removal is guarded by an existence check (mirroring `plan_gitdir_volume`'s `volume_exists` guard on creation), so removing a container whose volumes were already removed is a no-op for those volumes. `podman rm -f --volumes <container>` is retained for anonymous-volume cleanup.

## design (per the selected choice in [rm-container-write-volume-discovery](../choices/rm-container-write-volume-discovery.gen.md))

A new pure planner helper `plan_volume_rm` is added to [lib/containers.sh](../../../lib/containers.sh). It takes a nameref to the plan array and a volume name, and — when `volume_exists <name>` reports the volume as present — appends the token sequence `podman volume rm -f <name>` to the plan. This mirrors the existing `plan_gitdir_volume` helper's `volume_exists`-guarded emission pattern.

A shared helper `plan_container_volumes_rm` (or per-container inline emission) derives the full set of associated named volumes for a container from the project slug and the parsed write-mount dest list, using the naming helpers in [lib/naming.sh](../../../lib/naming.sh) (`gitdir_volume`, `netbox_worktree_volume`, `offbox_worktree_volume`, `netbox_write_volume`, `offbox_write_volume`, `dest_slug`), and calls `plan_volume_rm` for each.

## files to be created

None.

## files to be modified

- [lib/containers.sh](../../../lib/containers.sh):
  - Add `plan_volume_rm` and a container-volume-removal helper.
  - In `plan_recontain` and `plan_rebuild` (onbox): emit named-volume removal for the onbox gitdir volume after the `podman rm -f --volumes` step and before `plan_gitdir_volume`, so the gitdir volume is recreated.
  - In `plan_netbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_recontain`, `plan_offbox_rebuild`: emit named-volume removal for the worktree, gitdir and write volumes after the `podman rm -f --volumes` step and before the populate (`plan_netbox_populate`/`plan_offbox_populate`) and `plan_gitdir_volume` steps, so all volumes are recreated.
  - In `plan_netbox_rm_container` and `plan_offbox_rm_container`: accept the write-mount dest list (a new nameref parameter) and emit named-volume removal for the worktree, gitdir and write volumes alongside the existing `podman rm -f --volumes` and `podman rmi` steps.
- [talkbox.sh](../../../talkbox.sh):
  - In the `rm-container` branch of `sandbox_action`: pass the parsed `write_srcs`/`write_dsts` arrays through to `run_netbox_rm_container`/`run_offbox_rm_container`.
- [lib/containers.sh](../../../lib/containers.sh) executors `run_netbox_rm_container` / `run_offbox_rm_container`: accept and forward the write-mount dest list to the corresponding `plan_*_rm_container` function. The `run_netbox_rm_container`/`run_offbox_rm_container` fallback path (when the root image does not exist) must also remove the named volumes.

## relevant files to read during implementation

- [SPEC.md](../../../SPEC.md) — "image and container management" section.
- [lib/containers.sh](../../../lib/containers.sh) — all `plan_*` and `run_*` lifecycle functions, `plan_gitdir_volume`, `plan_volume_populate`, `plan_netbox_populate`, `plan_offbox_populate`, `volume_exists`, `execute_plan`.
- [lib/naming.sh](../../../lib/naming.sh) — volume-name derivation helpers.
- [talkbox.sh](../../../talkbox.sh) — `sandbox_action` dispatch, especially the `rm-container` branch and how `write_srcs`/`write_dsts` are produced by `mount_entries`.
- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) and [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) — existing lifecycle tests to update.

## key internal interfaces

- `plan_volume_rm <plan-nameref> <volume-name>` — emits `podman volume rm -f <volume-name>` when the volume exists.
- The container-volume-removal helper, taking `<plan-nameref> <project> <container> <dsts-nameref>`, deriving the worktree/gitdir/write volume names and calling `plan_volume_rm` for each. (For onbox, the dst list is empty and only the gitdir volume is removed.)
- `plan_netbox_rm_container` / `plan_offbox_rm_container` gain a new trailing nameref parameter for the write-mount dest array.
- `run_netbox_rm_container` / `run_offbox_rm_container` gain corresponding trailing nameref parameters, forwarded to the planners, and are called from `sandbox_action` with `write_dsts` (and `write_srcs` if needed for parity).

## tests

This phase requires tests. The existing lifecycle tests must be updated to reflect the new `podman volume rm` tokens in the plans, and new assertions added.

- **Unit tests** ([test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats)):
  - Update every `plan_recontain`/`plan_rebuild`/`plan_*_rm_container` assertion to account for the new `volume rm` subcommands in the emitted plan sequence (e.g. the `plan_subcommands` sequence gains `volume` steps, and the plan contains `podman volume rm -f <name>` tokens for the gitdir/worktree/write volumes).
  - Add cases verifying that only existing volumes are emitted for removal (the `volume_exists` guard), and that write volumes appear when write-mount dests are supplied.
  - Update the `plan_netbox_rm_container`/`plan_offbox_rm_container` unit tests to pass the new dest-array parameter.

- **End-to-end tests** ([test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats)):
  - Add a test verifying that after `onbox --rm-container`, the gitdir named volume no longer exists (`podman volume exists` returns false).
  - Add a test verifying that after `netbox --rm-container` (with a write mount), the worktree, gitdir and write named volumes no longer exist.
  - Strengthen the existing `onbox --recontain` test to assert that the gitdir volume is recreated fresh — e.g. commit inside the container, recontain, and confirm the previous container commit is no longer present in the git history of the recontained container.
  - Optionally add an analogous recontain-freshness check for netbox/offbox worktree or write volumes.
