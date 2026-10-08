# Phase 23b: `--rm-container`/recreate write-volume removal via container-mount inspection

#flow/redgreen #model/default

Resolves the issue [`--rm-container` leaks write volumes unless `--write` is repeated on the removal invocation](../../issues/rm-container-write-volumes-need-repeated-write.gen.md).

## specification

Implements the [SPEC.md](../../../SPEC.md) *image and container management* statements that `--rm-container` "removes the container, together with associated volumes" and that `--recontain`/`--rebuild` "recreate the container and all of its associated volumes": the write volumes created for the container are associated volumes regardless of the removal or recreation invocation's own write-mount arguments.

No other aspect of the specification is affected; everything else is already implemented and deferred here.

## external-facing functionality

- `netbox --rm-container` and `offbox --rm-container` remove every `<slug>.<container>.write.<dest-slug>` volume the container actually uses, without `--write` needing to be repeated on the removal invocation. Worktree, gitdir and root-image removal are unchanged.
- `netbox`/`offbox --recontain` and `--rebuild` remove the previous configuration's write volumes before repopulating, so no write volume from an earlier mount configuration survives a reconfiguration as a stale volume.

## files to create

None. Existing files are modified:

- [lib/containers.sh](../../../lib/containers.sh) — the mount-inspection discovery and the `plan_container_volumes_rm` signature change.
- [talkbox.sh](../../../talkbox.sh) — the `rm-container` dispatch branch drops the write-dsts threading.
- test files listed under *tests* below.

## files to read during implementation

- [SPEC.md](../../../SPEC.md) (image and container management)
- [lib/containers.sh](../../../lib/containers.sh) (`plan_container_volumes_rm`, `plan_rm_container`, `plan_recreate`, `run_rm_container_any`, the `run_netbox_rm_container`/`run_offbox_rm_container` delegates, `volume_exists`, `plan_volume_rm`)
- [lib/naming.sh](../../../lib/naming.sh) (write-volume naming)
- [talkbox.sh](../../../talkbox.sh) (`container_action` `rm-container` branch)
- [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats), [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats)
- [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats), [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats)
- the choice [write-volume discovery for `--rm-container` (revisited)](../choices/rm-container-write-volume-discovery-revisit.gen.md) and its predecessor [rm-container-write-volume-discovery](../choices/rm-container-write-volume-discovery.gen.md)
- the earlier issue [lifecycle verbs leave named volumes orphaned and reuse stale volumes on recreate](../../issues/lifecycle-verbs-leave-named-volumes-orphaned.gen.md) for context

## key internal interfaces

- A discovery helper in `lib/containers.sh` enumerates the container's named-volume mounts (via `podman inspect` over its `Mounts`) and filters those whose names match the `<project-slug>.<container>.write.` prefix. Since plans are assembled before execution, the container is inspected while it still exists, ahead of the emitted `podman rm`.
- `plan_container_volumes_rm` replaces its caller-provided write-dsts loop with the discovery helper and drops its write-dsts nameref parameter; the worktree and gitdir volumes continue to be removed by name. When the container does not exist, only the by-name removals apply.
- `plan_rm_container` and `plan_recreate` stop passing the write dsts to `plan_container_volumes_rm`; the dispatcher's `rm-container` branch and the `run_netbox_rm_container`/`run_offbox_rm_container` executors drop the write-dsts threading accordingly, mirroring the dead-parameter removal pattern of Phase 13a.
- Orphaned write volumes left behind by earlier failed removals are out of scope (per the selected choice) and remain untouched unless the container referencing them still exists.

## tests

Requires tests, per the [testing](../../../SPEC.md#testing) section of the specification, via `make test-unit` and `make test-e2e`:

- unit tests (`test/unit/containers.bats`/`test/unit/lifecycle.bats`): with a mocked inspect returning write-volume mounts, the plan emits a `podman volume rm` for each discovered write volume; with no container, the plan emits only the by-name worktree/gitdir removals.
- unit tests (`test/unit/dispatcher.bats`, podman shim): a `--rm-container` invocation without `--write` issues the inspect-based volume removals; the write-dsts threading is absent from the dispatch.
- end-to-end tests (`test/e2e/lifecycle.bats`/`test/e2e/netbox-offbox.bats`): after creating a `netbox` with a write mount, `netbox --rm-container` *without* repeating `--write` removes the write volume; a recreate with a changed write-mount configuration leaves no stale write volume from the previous configuration.

Superseded tests to remove or tighten: the existing `netbox --rm-container` e2e test repeats `--write "$data:/talkbox/wdata"` on the removal command — the repetition must be removed so the leak is caught, and the existing rm-container unit tests which pass the write-dsts parameter must be updated for the new signature.
