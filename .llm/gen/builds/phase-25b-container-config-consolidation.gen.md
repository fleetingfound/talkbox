# Phase 25b: per-container configuration consolidation of the container implementation

*Date: 2026-10-09*

Status: **SUCCESS**

## overview

Implemented the plan in [phase-25b-container-config-consolidation.gen.md](../plans/phase-25b-container-config-consolidation.gen.md): the three containers are now pure configuration over a single common implementation. A new [lib/definitions.sh](../../../lib/definitions.sh) holds the per-container configuration record as one case-based lookup (`container_config <field> <container>`: pasta suffix, nft enforcement, write style, named worktree volume, root image, populate policy, ordered default inheritance parents), and every former container-conditional branch point consults it. Behaviour is preserved exactly — every emitted podman command line is byte-identical — as pinned by the test revision already committed green at `c574e71`, which passed unchanged before and after this refactor.

## implemented changes

- [lib/definitions.sh](../../../lib/definitions.sh) (new) — the pure per-container configuration table; sourced by `talkbox.sh` and `lib/containers.sh`, no state or side effects.
- [lib/naming.sh](../../../lib/naming.sh) — deleted the 9 per-container one-liners (`onbox/netbox/offbox_container_name`, `netbox/offbox_worktree_volume`, `netbox/offbox_write_volume`, `netbox/offbox_root_image`); `project_base`/`slugify`/`project_slug`/`base_image_name`/`dest_slug`/`gitdir_volume` unchanged.
- [lib/containers.sh](../../../lib/containers.sh) — the four `*_of` dispatchers became generic `<project-slug>.<container>[.<kind>[.<qualifier>]]` one-liners (the onbox worktree keeps its degenerate mapping to the host project path); `container_net_suffix` was deleted and `pasta_net` reads the pasta-suffix field; `plan_netbox_populate`/`plan_offbox_populate` were replaced by the unified `plan_container_populate` (with `plan_volume_populate_from` choosing, per volume, between the inheritance source's corresponding volume and the host source) keyed by the populate-policy field; the `container_volumes`/`plan_container_volumes_rm` worktree guard, the `plan_recreate` commit guard, the `plan_rm_container` root-image guard, the `resolve_inheritance` onbox short-circuit, the `inherit_source` default chain (now walked from the config parent list) and the `run_container`/`run_recreate` nft guards all became config lookups; `inherit_source_for` uses `container_name_of`.
- [talkbox.sh](../../../talkbox.sh) — sources `lib/definitions.sh`; the write-mount branch (`mount_args` vs `mount_entries` + `mount_volume_args`) and the deny/allow computation are now selected by the `write_style` and `nft_enforce` config fields.
- [lib/mounts.sh](../../../lib/mounts.sh) — `mount_volume_args` builds write-volume names via the generic `write_volume_of`, deleting its `== offbox` branch.
- [MAP.gen.md](../../../MAP.gen.md) — new entry for `lib/definitions.sh`; rewritten entries for `lib/naming.sh`, `lib/containers.sh`, `talkbox.sh` and `lib/mounts.sh`.

No test file was touched; the revised suite from the test-revision stage (commit `c574e71`) is the pin for this refactor.

## verification

- `make test-unit`: 302/302 pass
- `make test-e2e`: 78/78 pass
- `make lint` and `make format`: green (the core files also pass `shfmt -d` and `shellcheck` with only the two pre-existing `SC2178` nameref warnings in `lib/mounts.sh`, unchanged by this refactor)

## resolution

No disputes; no new issues; no previously open issues were touched by this phase (the onbox-recontain issue was resolved in Phase 25a). The plan is marked complete in [INDEX.gen.md](../plans/INDEX.gen.md).
