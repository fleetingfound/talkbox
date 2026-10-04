# Phase 19: Consolidation of repeated container logic in `lib/containers.sh`

#flow/refactor #model/big

## aspect of the specification

No spec aspect is implemented or deferred. This is a maintainability refactor implementing the consolidation proposed in the [consolidation review](../reviews/containers-sh-consolidation-review.gen.md): [lib/containers.sh](../../../lib/containers.sh) encodes the three-container symmetry by copy-paste, with twelve function families in two or three near-identical copies (~40% of the file). Every behaviour defined by [SPEC.md](../../../SPEC.md) — container configuration, mounts, lifecycle verbs, root-filesystem and read-write-volume inheritance, network and deny enforcement — is preserved exactly.

## external-facing functionality

None. The CLI behaviour of `onbox`, `netbox` and `offbox` (including all lifecycle verbs and inheritance options) is unchanged; the e2e suite must pass unmodified.

## design decision

Per [Consolidation boundary and unit-test surface](../choices/containers-consolidation-boundary.gen.md) (executor-surface preservation): the fifteen `run_*` executor names survive as `lib/containers.sh`'s dispatch surface, becoming one-to-three-line delegates over unified cores; [talkbox.sh](../../../talkbox.sh) is not modified; the revised unit tests pin the podman command construction by exercising the executors with a logging podman shim.

## files to be created

None.

## files to be modified

- [lib/containers.sh](../../../lib/containers.sh) — replace the duplicated families with the unified cores below and reduce the executors to delegates (expected ~913 → ~550–600 lines).
- [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) — supersede the plan-function tests with executor-level podman-command tests (see [tests](#tests)).
- [MAP.gen.md](../../../MAP.gen.md) — rewrite the `lib/containers.sh` entry for the consolidated structure.

## relevant files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — the duplication inventory in the review maps directly onto it.
- [lib/naming.sh](../../../lib/naming.sh) — the per-container naming helpers behind the dispatch helpers.
- [lib/network.sh](../../../lib/network.sh) — `install_nft_deny` is a no-op for an empty deny set (relevant to the offbox invariant).
- [lib/git.sh](../../../lib/git.sh) — consumer of `run_sync_in_container`.
- [talkbox.sh](../../../talkbox.sh) — the `run_*` dispatch and the `ensure_base_image` call preceding onbox recontain.
- [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats), [test/unit/git-transport.bats](../../../test/unit/git-transport.bats).
- [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats), [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats), [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats) — unchanged behavioural reference for the lifecycle verbs and inheritance.
- [.llm/gen/reviews/containers-sh-consolidation-review.gen.md](../reviews/containers-sh-consolidation-review.gen.md) — the variation table (§3), proposed abstractions (§5) and invariants (§7).

## key internal interfaces

New unified cores, internal to [lib/containers.sh](../../../lib/containers.sh) (names per the review):

- `pasta_net` — network-string builder from a pasta suffix and the port list, with the per-container suffix dispatch (DNS-forward suffix for onbox/netbox, loopback restriction for offbox) replacing the three inline pasta blocks.
- Naming-dispatch helpers alongside the existing `container_name_of`: `root_image_of`, `worktree_volume_of`, `write_volume_of` — collapse the `case` dispatch in `plan_container_volumes_rm` and `container_sync_cmd`.
- `plan_container` — the single create-args planner, parameterized by container type and image, replacing `plan_onbox`/`plan_netbox`/`plan_offbox` (~100 duplicated lines; the largest win).
- `plan_recreate` — the single lifecycle planner, parameterized by container type, a rebuild flag and the inheritance source, replacing the six recontain/rebuild planners; it supplies the onbox dummy arrays internally and absorbs the netbox/offbox populate-signature asymmetry.
- `plan_rm_container` — repurposed as the container-parameterized rm-container planner (internal-only after this phase; emits the root-image rmi for netbox/offbox only).
- `plan_rm_image` — the vestigial `in_use` parameter is dropped (every caller passes `no`; the real guard is the imperative `image_in_use` check in the executor).
- `create_sandbox` — replaces `create_netbox`/`create_offbox`, unified on the planned form with the commit (when inheriting) first.
- `exec_in_container` and `stop_container` — the shared exec tail and the best-effort `podman stop` with the grace constant (currently duplicated at eleven sites).
- `run_container`, `run_recreate`, and unified rm-container / rm-image executor cores — parameterized by container type; the fifteen public `run_*` names delegate to them.

Dropped internal interfaces (their only remaining references are the superseded unit tests listed below):

- `plan_onbox`, `plan_netbox`, `plan_offbox`
- `plan_recontain`, `plan_rebuild`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild`
- `plan_netbox_rm_container`, `plan_offbox_rm_container`, `plan_netbox_rm_image`, `plan_offbox_rm_image`
- `create_netbox`, `create_offbox`

Preserved interfaces (names and signatures unchanged):

- The fifteen `run_*` executors: `run_onbox`, `run_netbox`, `run_offbox`, `run_recontain`, `run_rebuild`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild`, `run_rm_container`, `run_netbox_rm_container`, `run_offbox_rm_container`, `run_rm_image`, `run_netbox_rm_image`, `run_offbox_rm_image`.
- `inherit_source`, `source_exists`, `container_name_of`, `plan_volume_populate`, `plan_netbox_populate`, `plan_offbox_populate`, `plan_volume_rm`, `plan_gitdir_volume`, `plan_git_identity_env`, `plan_container_volumes_rm`, `execute_plan`, `ensure_base_image`, `container_exists`, `container_running`, `install_nft_deny_or_die`, `run_setup_in_container`, `image_in_use`, `prune_external_image_containers`, `exists_yn`, `volume_exists`, `container_sync_cmd`, `run_sync_in_container`.

Explicitly not consolidated (deferred): the semantic difference between `plan_netbox_populate` and `plan_offbox_populate`. The offbox netbox-volume fallback *is* the read-write-volume inheritance policy of [SPEC.md](../../../SPEC.md) and stays explicit in `plan_offbox_populate` (at most a shared loop skeleton).

## behavioural invariants to preserve

All are observable in the emitted podman command lines and therefore pinned by the revised tests:

1. offbox executors never invoke the nft install path, even when passed a non-empty deny set (the existing offbox shim test passes a deny entry and asserts zero `nsenter` invocations).
2. Base-image availability probes differ per path: onbox recontain/rebuild never probe (the caller in [talkbox.sh](../../../talkbox.sh) probed earlier); the sandbox recontain executors call `ensure_base_image` only when the inheritance source is base; the rebuild paths build inside the plan without a probe.
3. Commit-before-rm ordering in the recontain/rebuild plans — the inheritance source may be the very container being removed.
4. On the fresh-create path (`create_sandbox`), the commit (when inheriting) stays first and there is no rm.
5. onbox removes only the gitdir volume; netbox/offbox additionally remove the worktree and write volumes.
6. rm-container removes the root image only when `podman image exists` succeeds; the fallback path omits the rmi.
7. The onbox create path's gitdir volume creation is unified on the planned form (podman-log-identical to the current eager form).
8. The onbox recontain/rebuild executors run no nft install, no setup exec and no user command after executing the plan — only the stop; the sandbox recontain/rebuild executors run setup.sh (netbox after the nft step) and then stop.
9. The exec/stop tail: a non-empty command runs via `bash -c`, an empty command runs an interactive `/bin/bash`, the stop is best-effort, and the exec's exit status is returned.
10. Populate policy: netbox always copies from the host; offbox copies from the netbox volumes when inheriting from netbox and those volumes exist, and from the host otherwise; the gitdir volume is never populated.
11. `plan_netbox_populate` and `plan_offbox_populate` keep their exact current signatures (pinned by retained tests); `plan_recreate` absorbs their argument asymmetry internally.
12. `container_sync_cmd` emits byte-identical commands (its mount `case` collapses behind the worktree dispatch helper); its tests in [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) are unaffected.

## implementation order

Within the single refactor stage, follow the review's sequencing: the rm-image family and the stop helper first; then `pasta_net` + `plan_container`; then the naming dispatch + `plan_recreate`; then `exec_in_container` + `run_container`; then `create_sandbox` + `run_recreate` + the unified rm-container executor. The consolidation should also retire the now-unneeded `# shellcheck disable=SC2034` pragmas and reduce reliance on the file-level `SC2178` disable as the nameref plumbing is centralized.

## tests

The unit tests are revised before the implementation is touched: every revised and new test must pass against the current, unmodified implementation, because they pin the podman commands exactly as they are constructed today.

Superseded and removed (they test internal interfaces which are dropped):

- [test/unit/containers.bats](../../../test/unit/containers.bats): the 30 onbox plan-level tests — every test invoking `plan_onbox`, `plan_recontain` or `plan_rebuild` directly.
- [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats): the 33 netbox/offbox plan-level tests — every test invoking `plan_netbox`, `plan_offbox`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild` or `plan_offbox_rebuild` directly. The two tests that additionally call the surviving `plan_netbox_populate`/`plan_offbox_populate` keep their populate assertions (or re-express them) while their create-args assertions move to the executor level.
- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats): the 19 lifecycle plan-level tests — every test invoking `plan_recontain`, `plan_rebuild`, `plan_rm_container`, `plan_rm_image`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild`, `plan_netbox_rm_container`, `plan_offbox_rm_container` or `plan_netbox_rm_image` directly, including the two that pin the vestigial `in_use` parameter of `plan_rm_image`.

Retained unchanged: the `run_onbox`, `run_netbox`, `run_offbox`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild` and `run_*_rm_image` podman-shim tests; the `inherit_source`, `plan_volume_populate` and `plan_volume_rm` tests; the `prune_external_image_containers` tests; all of [test/unit/git-transport.bats](../../../test/unit/git-transport.bats).

Replacement unit tests, through the surviving executors with a logging podman shim (the shim fails `container exists` where the create path must run, and controls the `volume exists` / `image exists` / `inspect` / `ps` outcomes; `volume_exists` may alternatively be stubbed as today for existence-guarding assertions):

- create-args construction per container type: workdir, userns, the pasta network string with and without `-T` ports and the per-type suffix, cap drops, `--init` and its position relative to the image, GPU options, prompt and git-identity env vars, git-mount gating, global/project dotfiles and art mounts, read mounts read-only, write mounts as bind-mounts (onbox) vs volumes (netbox/offbox), container name, image selection, `sleep infinity`, interactive flags, and the absence of `--rm` and tmpfs.
- lifecycle verb command sequences per container: the rm → volume rm → volume create → create → start chain with commit-before-rm when inheriting, the build step first on rebuild, the populate `podman run` commands with their source/target mounts, and the start → nft → setup → command → stop ordering (nft for onbox/netbox, absent for offbox and for the onbox recontain/rebuild executors).
- inheritance as visible in the commands: commit source selection per `inherit_source`, `--fresh`/`--inherit` via the `TALKBOX_FRESH`/`TALKBOX_INHERIT` variables, and the offbox populate falling back between netbox volumes and the host.
- the rm verbs: the per-container volume removal set, the conditional root-image rmi, the in-use refusal for `--rm-image`, and the external-working-container pruning order.

Every assertion of the superseded tests must be preserved, re-expressed against the logged podman command lines (token membership within a command, ordering within a command, and ordering between commands). Merging several plan-level tests into fewer executor-level tests is acceptable; silent loss of coverage is not.

End-to-end: no new e2e tests and no e2e changes; the existing suite exercises the lifecycle verbs and inheritance externally and must pass unchanged.

Completion requires `make test-unit`, `make test-e2e`, `make lint` and `make format` all green.
