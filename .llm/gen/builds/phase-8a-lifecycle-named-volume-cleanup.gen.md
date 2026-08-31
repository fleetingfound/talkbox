# Phase 8a: Lifecycle verbs remove and recreate named volumes

Status: `SUCCESS`

This build implements [phase-8a-lifecycle-named-volume-cleanup.gen.md](../plans/phase-8a-lifecycle-named-volume-cleanup.gen.md), making `--rm-container` remove the container's associated named volumes and `--recontain`/`--rebuild` remove them so they are recreated cleanly, resolving [lifecycle-verbs-leave-named-volumes-orphaned.gen.md](../issues/lifecycle-verbs-leave-named-volumes-orphaned.gen.md) and implementing the "associated volumes" requirements of the image and container management section of [SPEC.md](../../../SPEC.md). The tests for the phase are described in [phase-8a-lifecycle-named-volume-cleanup.gen.md](../tests/phase-8a-lifecycle-named-volume-cleanup.gen.md); the implementation follows the selected Option A of [rm-container-write-volume-discovery.gen.md](../choices/rm-container-write-volume-discovery.gen.md), threading the parsed write-mount dest list into the `rm-container` path.

## Overview

- `lib/containers.sh` - adds the pure helpers `plan_volume_rm` (emits `podman volume rm -f <name>` when `volume_exists` reports the volume present, mirroring `plan_gitdir_volume`'s guard) and `plan_container_volumes_rm` (derives the worktree, gitdir and write volumes for a container from the project slug and the write-mount dest list via the `lib/naming.sh` helpers, calling `plan_volume_rm` for each; for onbox only the gitdir volume is removed).
- `lib/containers.sh` - `plan_recontain`, `plan_rebuild` and `plan_rm_container` (onbox) emit gitdir-volume removal after the `podman rm -f --volumes` step (and before `plan_gitdir_volume` for recontain/rebuild); `plan_netbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_recontain` and `plan_offbox_rebuild` emit worktree/gitdir/write-volume removal after the `rm` step and before the populate and `plan_gitdir_volume` steps.
- `lib/containers.sh` - `plan_netbox_rm_container` and `plan_offbox_rm_container` gain a trailing write-mount dest-array nameref parameter and emit removal for the worktree, gitdir and write volumes alongside the existing `podman rm` and `podman rmi` steps; `run_netbox_rm_container`/`run_offbox_rm_container` accept and forward the dest list, and their root-image-missing fallback path also removes the named volumes.
- `talkbox.sh` - the `rm-container` branch of `sandbox_action` passes the parsed `write_dsts` array through to `run_netbox_rm_container`/`run_offbox_rm_container`.

## Verification

- `make test-unit` - exit `0`; 174/174 tests passed.
- `make test-e2e` - exit `0`; 60/60 tests passed (including the strengthened `onbox --recontain` freshness test, the `onbox --rm-container` gitdir-volume test and the `netbox --rm-container` write-volume test).
- `shellcheck lib/containers.sh talkbox.sh` - no new findings (only pre-existing `SC1091`/`SC2153` info notes); `shfmt` reports no formatting changes.
