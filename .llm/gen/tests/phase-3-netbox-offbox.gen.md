# Tests: Phase 3 netbox and offbox containers

Linked plan: [phase-3-netbox-offbox.gen.md](../plans/phase-3-netbox-offbox.gen.md)

Summary: this phase adds failing tests for the Phase 3 features the plan defers from Phase 2 — the `netbox` and `offbox` containers, their volume-based worktree and write mounts, root filesystem inheritance via `podman commit`, the no-network volume-population helper container, the `--fresh`/`--inherit` options, the offbox network isolation, and the netbox/offbox lifecycle verbs.

The tests pin the following interfaces, which the implementation must provide so that the tests pass once the plan is implemented:

- `lib/naming.sh`: `netbox_container_name <project>` → `<project-slug>.netbox`, `offbox_container_name <project>` → `<project-slug>.offbox`, `dest_slug <dest>` → the hyphenated lowercase alphanumeric slug of a dest path, `netbox_worktree_volume`/`offbox_worktree_volume` → `<project-slug>.{netbox,offbox}.worktree`, `netbox_write_volume <project> <dest-slug>`/`offbox_write_volume <project> <dest-slug>` → `<project-slug>.{netbox,offbox}.write.<dest-slug>`, and `netbox_root_image`/`offbox_root_image` → `<project-slug>.{netbox,offbox}.root`.
- `lib/options.sh`: `parse_onbox_options` additionally records `--fresh` (field `ONBOX_FRESH`, default `no`) and `--inherit <source>` (field `ONBOX_INHERIT`, default empty).
- `lib/mounts.sh`: `mount_volume_args <out> <container> <defaults_file> <project> <home> [cli_spec ...]` fills `<out>` with write-mount `-v` flags that name volumes `<project-slug>.<container>.write.<dest-slug>` (for `netbox`/`offbox`), while `mount_args` keeps emitting read mounts as read-only bind-mounts.
- `lib/containers.sh`:
  - `inherit_source <target> <onbox_exists> <netbox_exists> <offbox_exists> <fresh> <inherit>` prints the root-image source: `base`, or the container type (`onbox`/`netbox`/`offbox`) to `podman commit`. Default chain: netbox→onbox, offbox→netbox→onbox→base; `--fresh` forces `base`; an explicit `--inherit` source is honoured only if that container exists, else `base`.
  - `plan_volume_populate <out> <target_volume> <source_kind> <source>` appends a `podman run --rm --network=none ...` helper argument list mounting the host source (or source volume) read-only (host) / read-write (volume) at `/talkbox/source` and the target volume read-write at `/talkbox/target`, copying the tree.
  - `plan_netbox <out> <project> <interactive> <read_mounts> <write_mounts> <ports> <image>` and `plan_offbox ...` mirror `plan_onbox`: worktree volume at `/working/<project-base>`, read mounts as read-only bind-mounts, write mounts as volumes, dotfiles bind-mounts, `--name=<container>`, cap-drops; offbox appends `,-i,lo,-I,talkbox0` to the pasta network string.
  - `plan_netbox_run`/`plan_offbox_run` (`create` → `start` → optional `exec`), and `plan_netbox_recontain`/`plan_offbox_recontain` (`commit` → `rm` → `create` → `start`, skipping `commit` for source `base`), `plan_netbox_rebuild`/`plan_offbox_rebuild` (`build` → `commit` → `rm` → `create` → `start`), `plan_netbox_rm_container`/`plan_offbox_rm_container` (`rm --volumes` plus `rmi <root image>`), and `plan_netbox_rm_image`/`plan_offbox_rm_image` (`rmi <base image>` with the in-use guard).

## New tests

Unit tests (`test/unit/`):

- `test/unit/naming.bats` (10 tests) - `netbox_container_name`/`offbox_container_name`, `dest_slug` (lowercase/hyphenation, leading/trailing-slash stripping), `netbox_worktree_volume`/`offbox_worktree_volume`, `netbox_write_volume`/`offbox_write_volume`, and `netbox_root_image`/`offbox_root_image`. Pins [SPEC.md §naming conventions](../../../SPEC.md) and the plan's "`<dest-slug>` derivation (`<dest>` converted to a hyphenated alphanumeric slug)" and netbox/offbox volume/root-image naming.
- `test/unit/options.bats` (4 tests) - `--fresh` sets `ONBOX_FRESH=yes`, `--inherit <source>` sets `ONBOX_INHERIT`, the empty default, and that neither flag is consumed as the command. Pins the plan's "parse `--fresh` and `--inherit <source>`" and [SPEC.md §inheritance options](../../../SPEC.md).
- `test/unit/mounts.bats` (4 tests) - `mount_volume_args` emits netbox and offbox write-mount volumes named `<slug>.{netbox,offbox}.write.<dest-slug>`, derives the dest-slug from the dest, and merges defaults-file and CLI specs. Pins [SPEC.md §read-write mounts](../../../SPEC.md) (netbox/offbox write-mount volume naming) and the plan's `lib/mounts.sh` volume-mount emission.
- `test/unit/netbox-offbox.bats` (20 tests) - the inheritance planner for all combinations of container existence, `--fresh` and `--inherit` (including base-image fallback when no source container exists); the volume-population planner for host-source and volume-source cases (asserting `podman run --rm --network=none`, read-only host source, read-write target volume, and a `cp` copy); `plan_netbox`/`plan_offbox` argument-list assembly (worktree volume, read-only read bind-mounts, write-mount volumes, dotfiles bind-mounts, pasta flags including offbox's `-i,lo,-I,talkbox0`, cap-drops, `--name`, image); and the netbox/offbox run plans. Pins [SPEC.md §netbox](../../../SPEC.md), [SPEC.md §offbox](../../../SPEC.md), [SPEC.md §filesystem inheritance](../../../SPEC.md), [SPEC.md §network](../../../SPEC.md) and [Choice: Volume Population Strategy](../choices/volume-population.gen.md) (no-network helper, read-only host source).
- `test/unit/lifecycle.bats` (9 tests) - `plan_netbox_recontain`/`plan_offbox_recontain` (including the `base`-source case that skips `commit`), `plan_netbox_rebuild`/`plan_offbox_rebuild`, `plan_netbox_rm_container`/`plan_offbox_rm_container` (`rm --volumes` plus `rmi <root image>`), and `plan_netbox_rm_image` with the in-use guard. Pins [SPEC.md §image and container management](../../../SPEC.md) ("`--recontain` and `--rebuild` also recreate the root image according to the root filesystem inheritance rules; `--rm-container` additionally removes the container's root image") and the plan's "lifecycle plan assembly for netbox/offbox including root-image commit/removal".

End-to-end tests (`test/e2e/netbox-offbox.bats`, 11 tests):

- `netbox container has internet access` - a `curl` probe to `https://example.com` succeeds (skipped when the host is offline).
- `netbox edits land in the worktree volume, never the host` - a host-written file is visible in netbox (volume populated from host), a file written in netbox does not appear on the host and is readable in a later netbox session.
- `netbox inherits the onbox root filesystem when onbox exists` - a root-filesystem marker written in `onbox` is visible in a subsequently created `netbox`.
- `offbox blocks internet access` - a bounded `curl --max-time 5` probe to `http://example.com` fails.
- `offbox writes land in its volumes, never the host` - a file written in offbox does not appear on the host and is readable in a later offbox session.
- `offbox created after netbox copies the netbox worktree and write volumes` - netbox writes into its worktree volume and a `--write` volume; a subsequently created offbox with the same `--write` sees the netbox worktree file, the netbox write-volume file and the host-source file.
- `netbox --fresh ignores existing containers and copies from host` - `netbox` (without `--fresh`) inherits an onbox root marker; after `--rm-container`, `netbox --fresh` starts from the base image without the marker.
- `--inherit selects the explicit inheritance source` - onbox and a `--fresh` netbox each write a different marker into their root filesystem; `offbox --inherit onbox` shows the onbox marker.
- `netbox --rm-container removes the container and its root image` - after creating netbox (with onbox present, so a root image exists) `--rm-container` removes the container and `<slug>.netbox.root`.
- `netbox --rm-image removes the base image` - after creating netbox, `--rm-image` removes `talkbox/base:latest`.
- `netbox --rebuild commits onbox and recreates the container` - with onbox present, `--rebuild` creates `<slug>.netbox.root` and the recreated netbox inherits the onbox root marker.

## Tests edited

- `test/unit/options.bats` - `setup()` now also initialises the new record fields `ONBOX_FRESH` and `ONBOX_INHERIT`. Evidence from the plan: "Modify `lib/options.sh` - parse `--fresh` and `--inherit <source>`" and "`lib/options.sh`: the inheritance selection is exposed alongside the other parsed flags."
- `test/e2e/helpers.bash` - `onbox_ctr_name` now derives the slug via a new shared `project_slug_e2e` helper (identical output), which is also reused by the new `netbox_ctr_name`, `offbox_ctr_name` and `project_slug_e2e` helpers; a new generic `run_talkbox <project> <talkbox> <container> [args ...]` runner invokes `talkbox.sh` under `systemd-run`. Justification: the e2e tests need netbox/offbox container names and invocations with extra flags (`--write`, `--fresh`, `--inherit`, lifecycle verbs); the refactor preserves the existing onbox behaviour byte-for-byte.
- `test/unit/lifecycle.bats` - added the `array_has_none` helper alongside the existing `array_contains` for the new base-source recontain assertion (no `podman commit` emitted). No existing assertions were changed.

## Tests removed

None. All pre-existing tests remain consistent with the plan: they pin the `onbox` behaviour (bind-mount worktree, persistent container, lifecycle verbs, mounts/ports parsing) which Phase 3 leaves unchanged, and the plan defers git mounts to Phase 4, which no existing test exercises.
