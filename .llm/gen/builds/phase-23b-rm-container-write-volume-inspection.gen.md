# Build: Phase 23b — `--rm-container`/recreate write-volume removal via container-mount inspection

Status: **SUCCESS** — `make test-unit` (317/317) and `make test-e2e` (75/75) pass.

Implements [Phase 23b](../plans/phase-23b-rm-container-write-volume-inspection.gen.md) (selected choice: Option B, container-mount inspection), resolving the issue [`--rm-container` leaks write volumes unless `--write` is repeated on the removal invocation](../issues/rm-container-write-volumes-need-repeated-write.gen.md).

## summary

- [lib/containers.sh](../../../lib/containers.sh): new `container_write_volumes` discovery helper — when the container exists, inspects `podman inspect -f '{{range .Mounts}}{{.Name}} {{end}}' <ctr>` at plan time (ahead of the emitted `podman rm`) and collects every mount name matching the `<project-slug>.<container>.write.` prefix; `plan_container_volumes_rm` drops its write-dsts nameref parameter and removes the worktree/gitdir volumes by name plus each discovered write volume via `plan_volume_rm`; `plan_recreate` and `plan_rm_container` stop passing write dsts; `run_rm_container_any`/`run_rm_container`/`run_netbox_rm_container`/`run_offbox_rm_container` drop the write-dsts threading (the Phase 13a dead-parameter pattern), leaving `container_volumes` as the rollback-only enumeration for `rollback_creation_and_die`.
- [talkbox.sh](../../../talkbox.sh): the `rm-container` dispatch branch calls `run_${container}_rm_container` with only the project path.

Behaviour: `netbox`/`offbox --rm-container` remove every write volume the container actually mounts without repeating `--write`, and `--recontain`/`--rebuild` drop the previous configuration's write volumes before repopulating (verified end-to-end by the new e2e `--rm-container` and `--recontain` stale-volume tests). Worktree, gitdir and root-image removal are unchanged; orphaned write volumes from earlier failed removals remain out of scope per the selected choice.

## links

- Plan: [phase-23b-rm-container-write-volume-inspection](../plans/phase-23b-rm-container-write-volume-inspection.gen.md) — the specification for this phase.
- Choice: [rm-container-write-volume-discovery-revisit](../choices/rm-container-write-volume-discovery-revisit.gen.md) — selected Option B (container-mount inspection) over name-pattern listing.
- Resolved issue: [rm-container-write-volumes-need-repeated-write](../issues/rm-container-write-volumes-need-repeated-write.gen.md) — the leak this build fixes.
