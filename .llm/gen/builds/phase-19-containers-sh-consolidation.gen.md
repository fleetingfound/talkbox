# Build: Phase 19 — consolidation of repeated container logic in `lib/containers.sh`

status: SUCCESS

## summary

Implemented the [Phase 19 plan](../plans/phase-19-containers-sh-consolidation.gen.md): [lib/containers.sh](lib/containers.sh) was rewritten from 913 to 606 lines by replacing the twelve copy-pasted onbox/netbox/offbox function families with unified container-parameterized cores, while keeping the fifteen `run_*` executor names (talkbox.sh's dispatch surface) as one-to-three-line delegates. [talkbox.sh](talkbox.sh) was not modified and no test under `test/` was touched; the executor-level unit tests revised in the preceding commit pass unmodified.

## changes

- [lib/containers.sh](lib/containers.sh):
  - new naming-dispatch helpers `root_image_of`, `worktree_volume_of`, `write_volume_of` alongside the existing `container_name_of`, collapsing the `case` dispatch in `plan_container_volumes_rm` and `container_sync_cmd`;
  - `pasta_net`/`container_net_suffix` replace the three inline pasta network-string blocks (DNS-forward suffix for onbox/netbox, `-i,lo,-I,talkbox0` for offbox);
  - `plan_container` replaces `plan_onbox`/`plan_netbox`/`plan_offbox` as the single create-args planner;
  - `plan_recreate` replaces the six recontain/rebuild planners (build first on rebuild, commit-before-rm when inheriting, the onbox dummy arrays injected by its delegates and the netbox/offbox populate-signature asymmetry absorbed internally);
  - `plan_rm_container` is repurposed as the container-parameterized rm-container planner (root-image rmi for netbox/offbox only, guarded by `podman image exists`), and `plan_rm_image` drops the vestigial `in_use` parameter;
  - `create_sandbox` replaces `create_netbox`/`create_offbox` and also carries the onbox fresh-create path, unified on the planned form with the commit (when inheriting) first;
  - `stop_container` and `exec_in_container` extract the best-effort stop and the exec/stop/return tail;
  - `run_container`, `run_recreate`, `run_rm_container_any` and `run_rm_image_any` are the executor cores; `inherit_source_for` collapses the repeated four-`exists_yn` `inherit_source` substitution;
  - dropped: `plan_onbox`, `plan_netbox`, `plan_offbox`, `plan_recontain`, `plan_rebuild`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild`, `plan_netbox_rm_container`, `plan_offbox_rm_container`, `plan_netbox_rm_image`, `plan_offbox_rm_image`, `create_netbox`, `create_offbox`.
- [MAP.gen.md](MAP.gen.md) — the `lib/containers.sh` entry rewritten for the consolidated structure.

## behavioural invariants

All invariants listed in the plan are preserved and pinned by the unchanged unit suite: offbox never installs nft (even with a non-empty deny set); onbox recontain/rebuild probe no image and run no nft/setup/user command after the plan; sandbox recontain probes the base image only when inheriting from base and rebuild builds inside the plan; commit-before-rm ordering; onbox removes only the gitdir volume; rm-container emits the root-image rmi only when it exists; the onbox gitdir-volume creation is unified on the planned form (podman-log-identical); the exec/stop tail and its status propagation; and the offbox netbox-volume populate fallback stays explicit in `plan_offbox_populate`.

## verification

- `make test-unit`: 247/247 pass.
- `make test-e2e`: 76/76 pass (requires `expect` on `PATH`; provided via `/tmp/opencode/expect-debs/bin`).
- `make lint` and `make format`: green (`lib/containers.sh` additionally verified with shellcheck and shfmt directly — only the unavoidable `SC1091` info diagnostics remain, identical to the pre-refactor file; the file-level `SC2178` disable is retained as nameref plumbing still triggers it).

## notes

- The e2e suite initially failed three `expect`-driven interactive tests; this was an environment issue (`expect` missing from `PATH` after a reboot of the sandbox), reproduced identically against the pre-refactor implementation, and resolved by providing `expect` — not a regression of this change.
