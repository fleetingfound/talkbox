# Phase 3: netbox and offbox containers

Status: `SUCCESS`

This build implements [phase-3-netbox-offbox.gen.md](../plans/phase-3-netbox-offbox.gen.md), which adds the `netbox` and `offbox` containers, their volume-based worktree and write mounts, root filesystem inheritance via `podman commit`, the no-network volume-population helper container, the `--fresh`/`--inherit` options, the offbox network isolation, and the netbox/offbox lifecycle verbs.

The verdict [phase-3-mount-write-assertion-contradiction.gen.md](../verdicts/phase-3-mount-write-assertion-contradiction.gen.md) resolves the earlier dispute [phase-3-mount-write-assertion-contradiction.gen.md](../disputes/phase-3-mount-write-assertion-contradiction.gen.md), which found two unit tests internally contradictory (they required the read-only read bind-mount `/host/data:/talkbox/wdata:ro` while asserting no argument contains `/talkbox/wdata:ro`); the tests were rescoped to the write-volume element only, and no issue documents were created.

## Overview

- `lib/naming.sh` - adds `netbox_container_name`/`offbox_container_name`, `dest_slug` (`<dest>` converted to a hyphenated alphanumeric slug), `netbox_worktree_volume`/`offbox_worktree_volume`, `netbox_write_volume`/`offbox_write_volume` and `netbox_root_image`/`offbox_root_image`.
- `lib/options.sh` - parses `--fresh` (field `ONBOX_FRESH`, default `no`) and `--inherit <source>` (field `ONBOX_INHERIT`, default empty).
- `lib/mounts.sh` - extracts the shared `mount_entries` collector (ordered, deduplicated source/dest pairs) reused by `mount_args` (read-only bind-mounts) and the new `mount_volume_args` (write mounts as named volumes `<slug>.<container>.write.<dest-slug>`).
- `lib/containers.sh` - the pure `inherit_source` root-image planner (onbox<-base, netbox<-onbox, offbox<-netbox<-onbox<-base, with `--fresh`/`--inherit`), the no-network `plan_volume_populate` helper (`podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000` with the host source read-only / source volume read-write and the target volume read-write), the `plan_netbox`/`plan_offbox` argument assemblers (worktree volume, read-only read bind-mounts, write-mount volumes, dotfiles bind-mounts, pasta flags including offbox's `-i,lo,-I,talkbox0`, cap-drops, `--name`, image), the netbox/offbox run and lifecycle plans (`plan_netbox_run`/`plan_offbox_run`, `plan_{netbox,offbox}_recontain`/`_rebuild`/`_rm_container`/`_rm_image`), and the `run_*` executors which commit the inherited root image, populate the volumes and drive the persistent containers.
- `talkbox.sh` - routes `netbox`/`offbox` through the shared `sandbox_action`, which assembles read mounts, write-mount volume args, the write source/dest pairs needed for volume population, and ports, and dispatches the lifecycle verbs.

## Verification

- `make test-unit` - exit `0`; 117/117 tests passed (including the two disputed unit tests after their repair).
- `make test-e2e` - exit `0`; 33/33 tests passed.
- `make lint` - exit `0`; ShellCheck clean on all modified scripts.
- `make format` - `shfmt` clean on all modified scripts.
