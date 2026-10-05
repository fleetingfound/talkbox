# Phase 20f: convergence of create_sandbox and plan_recreate in lib/containers.sh

#flow/refactor #model/default

## scope

Resolves duplication item §6 (the largest remaining structural duplication in `lib/`) of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md).

- Implemented, in [lib/containers.sh](../../../lib/containers.sh):
  - a shared inheritance-resolution helper resolving `(container, rebuild, project)` to the inheritance source and image, subsuming the near-identical resolution heads of `create_sandbox` and `run_recreate`/`plan_recreate` — including the base-image ensure/build decision, which today differs only in that the rebuild path plans an explicit `podman build` where the create path probes with `ensure_base_image`. The helper encodes the current conditions exactly so both paths keep their observable behaviour;
  - a shared plan assembler for the common tail used by both: the per-container volume-populate case dispatch (`plan_netbox_populate`/`plan_offbox_populate`), the gitdir-volume creation plan, and the `plan_container` → `podman create` assembly. `plan_recreate` keeps its head (build, commit-before-rm, `podman rm`, volume removal) and `podman start` tail; `create_sandbox` keeps its create-only execution semantics.
- Deferred: the naming dispatch layers stay untouched ([naming-dispatch-consolidation choice](../../choices/naming-dispatch-consolidation.gen.md)); the `run_*` executor delegates are preserved per the Phase 19 [consolidation-boundary choice](../../choices/containers-consolidation-boundary.gen.md).

No aspect of `SPEC.md` changes; this refactors the "filesystem inheritance" and "image and container management" implementations. External-facing behaviour is unchanged: every podman command sequence emitted by the executors (commit-before-rm ordering, populate ordering, create/start ordering, nft/setup placement) is identical.

## files to be created

None. Modified: [lib/containers.sh](../../../lib/containers.sh). Update its [MAP.gen.md](../../../MAP.gen.md) description.

## relevant files to be read

- [lib/containers.sh](../../../lib/containers.sh)
- [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) (executor-level behaviour-pinning tests)

## key internal interfaces

- New internal helpers: the inheritance-resolution helper and the populate→gitdir→create plan assembler. `create_sandbox`, `plan_recreate`, `plan_container`, `plan_netbox_populate`, `plan_offbox_populate` and the `run_*` executors keep their current signatures and dispatch surface.

## tests

Unit tests required, ensuring podman commands are constructed correctly. The executor-level tests across [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) and [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) already pin the emitted podman command sequences for create, recontain, rebuild, inheritance and volume-populate ordering with a logging podman shim, and the direct `plan_volume_populate`/`plan_netbox_populate`/`plan_offbox_populate` tests pin the populate command arrays; all must keep passing unchanged. The pinning pass should close any gap between what the two code paths emit where a shared helper now guarantees their agreement (e.g. the create-path and recreate-path gitdir-volume and create-argument assembly). No existing tests are superseded or removed — no tested internal interface is dropped.
