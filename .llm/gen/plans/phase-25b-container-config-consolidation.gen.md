# Phase 25b: per-container configuration consolidation of the container implementation

#flow/refactor #model/big

## aspect of the specification

No spec aspect is newly implemented and none is deferred. This is a behaviour-preserving refactor which completes the architecture that [SPEC.md](../../../SPEC.md)'s implementation section prescribes (one `talkbox.sh` acting as `onbox`, `netbox` and `offbox`) by making the three containers pure configuration over a single common implementation, as proposed in the [common-implementation review](../reviews/container-common-implementation.gen.md). Every externally observable behaviour — container configuration, mounts, lifecycle verbs, root-filesystem and read-write-volume inheritance, network and deny enforcement, git transport — is preserved exactly, including the Phase 25a recontain behaviour.

## external-facing functionality

None. The CLI behaviour of `onbox`, `netbox` and `offbox` (including all lifecycle verbs, inheritance options and subcommands) is unchanged, and the podman command sequences emitted per container are byte-identical. The e2e suite must pass unmodified.

## design decisions

- [Per-container configuration mechanism](../choices/container-config-mechanism.gen.md): a new `lib/definitions.sh` defines one pure case-based lookup (`container_config <field> <container>`) reading as a table; sourced by `talkbox.sh` and `lib/containers.sh`.
- [Consolidation scope](../choices/container-consolidation-scope.gen.md): full config-driven — every container-conditional branch point becomes a config lookup, including the default inheritance chains as ordered parent lists; the 9 naming one-liners and the 2 populate planners are removed.
- [Post-consolidation naming interface](../choices/container-naming-interface.gen.md): the four `*_of` dispatchers keep their names and signatures and become generic one-liners over the container argument; the 9 dedicated one-liners are deleted.

## files to be created

- `lib/definitions.sh` — the per-container configuration record: a single case-based lookup function over a field name and the container, plus nothing else (no state, no side effects). Fields (names indicative): pasta suffix; nft deny/allow enforcement (yes/no); write style (bind/volume); named worktree volume (yes/no); root image (yes/no); populate policy (none / host / source-else-host); default inheritance parents (ordered list, empty meaning base).

## files to be modified

- [lib/naming.sh](../../../lib/naming.sh) — delete the 9 per-container one-liners (`onbox/netbox/offbox_container_name`, `netbox/offbox_worktree_volume`, `netbox/offbox_write_volume`, `netbox/offbox_root_image`); keep `project_base`/`slugify`/`project_slug`/`base_image_name`/`dest_slug`/`gitdir_volume` unchanged.
- [lib/containers.sh](../../../lib/containers.sh) — implement the four `*_of` dispatchers as generic `<project-slug>.<container>[.<kind>[.<qualifier>]]` one-liners (sourcing `lib/definitions.sh`); drop `container_net_suffix` (`pasta_net` consults the config); replace `plan_netbox_populate`/`plan_offbox_populate` with one unified populate planner keyed by the populate-policy field; collapse the remaining branch points (see key internal interfaces); `inherit_source` keeps its signature and its `--fresh`/`--inherit` logic, with the default chains walked from the config parent list.
- [talkbox.sh](../../../talkbox.sh) — source `lib/definitions.sh`; the write-mount branch (`mount_args` vs `mount_entries` + `mount_volume_args`) and the `!= offbox` deny/allow computation become config lookups (write style; nft enforcement).
- [lib/mounts.sh](../../../lib/mounts.sh) — `mount_volume_args` builds write-volume names via the generic `write_volume_of`, deleting its `== offbox` branch.
- [test/unit/naming.bats](../../../test/unit/naming.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats), [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats), [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) — the consolidation-consistent test revision described under tests (completed before the implementation is touched).
- [MAP.gen.md](../../../MAP.gen.md) — new entry for `lib/definitions.sh`; rewritten entries for `lib/naming.sh`, `lib/containers.sh`, `talkbox.sh` and `lib/mounts.sh`.

## relevant files to read during implementation

- [.llm/gen/reviews/container-common-implementation.gen.md](../reviews/container-common-implementation.gen.md) — the variation table, the config-record proposal and the feasibility notes.
- [lib/containers.sh](../../../lib/containers.sh), [lib/naming.sh](../../../lib/naming.sh), [talkbox.sh](../../../talkbox.sh), [lib/mounts.sh](../../../lib/mounts.sh) — the branch points and dedicated functions being consolidated.
- [lib/network.sh](../../../lib/network.sh) — `install_nft_deny` (empty deny set: no invocation), the nft-enforcement consumer.
- [SPEC.md](../../../SPEC.md) — the per-container sections (mounts, containers, filesystem inheritance, network, image and container management), whose per-container data points are exactly the config fields.
- The test files listed above; [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats), [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats), [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats) — unchanged behavioural reference.
- [test/unit/helpers.bash](../../../test/unit/helpers.bash) — `load_lib`/`load_container_libs` and the podman shim.

## key internal interfaces

New:

- `container_config <field> <container>` — the single lookup; consumed by `talkbox.sh` (write style, nft enforcement), `pasta_net` (pasta suffix), `run_container`/`run_recreate` (nft enforcement), `container_volumes`/`plan_container_volumes_rm` (named worktree volume), `plan_recreate`/`plan_rm_container`/`resolve_inheritance` (root image), the unified populate planner (populate policy), and `inherit_source` (default parent list).
- The unified populate planner replacing `plan_netbox_populate`/`plan_offbox_populate`, invoked from `plan_populate_and_create` for every container: for each of the worktree and write volumes, copy from the inheritance source's corresponding volume when the target's policy is source-else-host, the source is volume-backed and the volume exists, and from the host otherwise; no populate commands at all for a none policy.

Preserved (names and signatures unchanged, and therefore the surfaces the revised tests pin):

- The executor cores `run_container`, `run_recreate`, `run_rm_container`, `run_rm_image`, `create_sandbox`, `execute_plan` and the planners `plan_container`, `plan_populate_and_create`, `plan_recreate`, `plan_rm_container`, `plan_rm_image`, `plan_volume_populate`, `plan_gitdir_volume`, `plan_container_volumes_rm`.
- `container_name_of`, `root_image_of`, `worktree_volume_of`, `write_volume_of` (now generic one-liners), `gitdir_volume`, `inherit_source`, `source_exists`, `pasta_net`, `mount_args`, `mount_entries`, `mount_volume_args`.

Dropped (all references live in the superseded tests listed under tests, or in the functions being replaced):

- The 9 naming one-liners; `container_net_suffix`; `plan_netbox_populate`; `plan_offbox_populate`.

Branch points collapsed behind config lookups (per the review's inventory): the `talkbox.sh` write-mount and deny/allow branches; the `container_volumes`/`plan_container_volumes_rm` worktree-volume guard; the `plan_populate_and_create` populate dispatch; the `plan_recreate` commit guard; the `plan_rm_container` root-image guard; the `resolve_inheritance` onbox short-circuit; the `run_container`/`run_recreate` nft guard; the `inherit_source` default-chain case; the `mount_volume_args` offbox branch; the `container_net_suffix` case.

## behavioural invariants to preserve

All are observable in the emitted podman command lines and pinned by the revised unit tests and the unchanged e2e suite:

1. Every per-container name is byte-identical: `<project-slug>.<container>` container names, `.worktree`/`.write.<dest-slug>`/`.root`/`.gitdir` volume and image names. `worktree_volume_of` for onbox keeps returning the host project path (the bind-mount degenerate case). The onbox values of `root_image_of`/`write_volume_of` are unspecified (never emitted; call sites guarded by the root-image and write-style config fields) and must not be pinned by tests.
2. Populate policy: netbox always seeds from the host, even under an explicit `--inherit offbox` (a target-container property per `SPEC.md`, not derived from the source); offbox seeds from the netbox volumes only when inheriting from netbox and those volumes exist, from the host otherwise; onbox issues no populate commands. The gitdir volume is never populated; every populate `podman run` keeps the exact no-network prefix.
3. Inheritance: identical source resolution for every `--fresh`/`--inherit`/default combination (pinned by the surviving `inherit_source` tests); commit-before-rm ordering in recontain/rebuild; the base-image probe and build placement per path.
4. Network: identical `pasta:` strings per container (DNS-forward suffix for onbox/netbox, `-i,lo,-I,talkbox0` for offbox) and identical cap drops.
5. Start-time tails: nft install (non-empty deny set) for onbox/netbox before `setup.sh`, which runs for all three, on both create and recontain/rebuild (Phase 25a).
6. Removal verbs: onbox removes only the gitdir volume; netbox/offbox additionally the worktree and inspected write volumes and their root images when present; `--rm-image` guards and pruning unchanged.
7. `mount_volume_args` emits byte-identical `-v` tokens; onbox write mounts stay bind-mounts, netbox/offbox write mounts stay named volumes.

## implementation order

Within the single refactor stage, after the test revision is green against the existing implementation: `lib/definitions.sh` and the genericized `*_of` dispatchers first (they are self-contained); then `pasta_net`, `mount_volume_args` and the `talkbox.sh` branches; then the unified populate planner and `plan_populate_and_create`; then `inherit_source`/`resolve_inheritance`/`plan_recreate`/`plan_rm_container`; then the `run_*` start-time tails. `make lint` and `make format` must stay green throughout.

## tests

Per the flow, the suite is revised first and must pass against the current, unmodified (post-Phase 25a) implementation, because every revised and new test pins the podman commands and function outputs exactly as constructed today; the implementation stage must then pass the revised suite unchanged.

Superseded and rewritten in the test revision:

- [test/unit/naming.bats](../../../test/unit/naming.bats): the per-container one-liner tests (container names, worktree/write/root names) — re-expressed against the surviving `*_of` dispatchers for all three containers (loading `lib/containers.sh`), covering the onbox degenerate worktree mapping; without pinning the unspecified onbox `root_image_of`/`write_volume_of` values.
- [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats): every test invoking `plan_netbox_populate`/`plan_offbox_populate` directly — re-expressed through the surviving `plan_populate_and_create` and the executors with the podman shim, preserving the populate coverage (no-network prefix, host vs source-volume seeding, gitdir never populated); name construction via `netbox_write_volume`/`offbox_write_volume`/`*_container_name` — replaced by `write_volume_of`/`container_name_of` or literal expected names.
- [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/git-transport.bats](../../../test/unit/git-transport.bats): the `onbox_container_name` call sites — replaced by `container_name_of`.

Consistency with the consolidation (also part of the revision):

- Where tests pin the shared pipeline rather than per-container semantics, they are folded into data-driven loops over the three containers (as the existing `run_recreate` ordering test already does over netbox/offbox), so the suite no longer encodes the per-container implementation structure and covers the consolidated implementation symmetrically. Genuinely per-container expectations (pasta suffix, write style, populate policy, inheritance chains, nft applicability) remain as per-container data in the tests.
- No test may reference the dropped functions (`onbox/netbox/offbox_container_name`, `netbox/offbox_worktree_volume`, `netbox/offbox_write_volume`, `netbox/offbox_root_image`, `container_net_suffix`, `plan_netbox_populate`, `plan_offbox_populate`).
- No dedicated unit test of `container_config` is possible before the module exists; the table's correctness is pinned through the command-line-level tests above (every field is observable in emitted podman commands), and the implementation stage adds no new tests.

Retained unchanged: the `inherit_source`/`source_exists` tests (signature preserved), the executor and planner podman-shim tests, [test/unit/options.sh](../../../test/unit/options.sh), [test/unit/mounts.sh](../../../test/unit/mounts.sh), [test/unit/network.bats](../../../test/unit/network.bats), [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) (beyond the naming call-site replacement), all of [test/unit/merge.bats](../../../test/unit/merge.bats), [test/unit/common.bats](../../../test/unit/common.bats) and the harness tests.

End-to-end: no e2e changes; the existing suite exercises the three containers externally and must pass unchanged.

Completion requires `make test-unit`, `make test-e2e`, `make lint` and `make format` all green, with the revised unit suite passing both immediately before the implementation change (test-revision stage) and after it (implementation stage).
