# Phase 20d: shared no-network run prefix and git-mount plan tokens

#flow/refactor #model/default

## scope

Resolves duplication item §8 of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md).

- Implemented: two small plan-token helpers centralising the repeated podman argument groups so they cannot drift between call sites:
  - a helper emitting the no-network temporary-container prefix (`podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000`), used by `gitdir_bundle_cmd` in [lib/git.sh](../../../lib/git.sh), `plan_volume_populate` in [lib/containers.sh](../../../lib/containers.sh) and the temporary-container branch of `container_sync_cmd` in [lib/containers.sh](../../../lib/containers.sh) (the latter appends `--workdir` afterwards);
  - a helper emitting the shared git-mount tokens (the read-only host git dir mount, the gitdir volume mount and the read-only `merge.sh` mount) used by `plan_container` and `container_sync_cmd`.
- Deferred: nothing else; the placement may reuse an existing shared module visible to both [lib/git.sh](../../../lib/git.sh) and [lib/containers.sh](../../../lib/containers.sh) rather than creating a new file, since these are pure token emitters.

No aspect of `SPEC.md` changes; this refactors the "implementation" section's no-network temporary-container rule and the git-mount assembly. External-facing functionality is unchanged: every emitted podman command line is byte-identical, including token ordering at each call site.

## files to be created

None (the helpers land in an existing shared module; no new file is expected). Modified: [lib/common.sh](../../../lib/common.sh) (or another existing shared module), [lib/git.sh](../../../lib/git.sh), [lib/containers.sh](../../../lib/containers.sh). Update [MAP.gen.md](../../../MAP.gen.md) descriptions of the modified files.

## relevant files to be read

- [lib/git.sh](../../../lib/git.sh), [lib/containers.sh](../../../lib/containers.sh), [lib/common.sh](../../../lib/common.sh)
- [test/unit/git.bats](../../../test/unit/git.bats), [test/unit/git-transport.bats](../../../test/unit/git-transport.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) (command-construction tests)

## key internal interfaces

- New no-network run prefix helper (nameref out-array) and new git-mount tokens helper (nameref out-array), placed in a module sourced by both consumers. The public signatures of `gitdir_bundle_cmd`, `plan_fetch`, `plan_volume_populate`, `plan_netbox_populate`, `plan_offbox_populate`, `plan_container` and `container_sync_cmd` are unchanged.

## tests

Unit tests required, ensuring podman commands are constructed correctly: the existing tests that assert the exact command arrays — `plan_fetch`/`gitdir_bundle_cmd` in [test/unit/git.bats](../../../test/unit/git.bats) and [test/unit/git-transport.bats](../../../test/unit/git-transport.bats), `plan_volume_populate`/`plan_netbox_populate`/`plan_offbox_populate` in [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), and the `container_sync_cmd` no-network run test in [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) — must keep passing unchanged, which pins the exact prefix and mount token ordering. No existing tests are superseded or removed.
