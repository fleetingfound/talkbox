# Build: Phase 24 — Remove the per-container `run_*` dispatch wrappers

Status: **SUCCESS** (all 315 unit tests and all 78 e2e tests pass; `make lint` and `make format` clean).

Implements [Phase 24](../plans/phase-24-remove-run-dispatch-wrappers.gen.md), a behaviour-preserving simplification of the internal dispatch surface: the nineteen per-container `run_*` wrappers, the `_any` suffix on the removal cores and the test-only `list_submodule_git_dirs` helper are removed, and `container_action` dispatches directly to the container-parameterised cores.

## Changes

### [talkbox.sh](../../../talkbox.sh) — direct core dispatch

- `container_action` now calls the cores by name with the container as the leading argument: the default verb calls `run_container`, `recontain`/`rebuild` call `run_recreate` with the rebuild flag `no`/`yes`, and `rm-container`/`rm-image` call `run_rm_container`/`run_rm_image` with only the project (write volumes are still discovered by inspecting the container). `fetch`/`merge`/`sync` were already direct.
- The conditional `write_entries` padding is gone: the `write_srcs`/`write_dsts` namerefs are always passed positionally (they stay empty for `onbox`, where `mount_entries` is never invoked), so the `no_mounts` dummy arrays inside the wrappers disappear from the dispatch entirely.

### [lib/containers.sh](../../../lib/containers.sh) — wrapper family deleted, `_any` suffix dropped

- Deleted all nineteen wrappers: `run_onbox`/`run_netbox`/`run_offbox`, `run_recontain`/`run_onbox_recontain`/`run_rebuild`/`run_onbox_rebuild`/`run_netbox_recontain`/`run_offbox_recontain`/`run_netbox_rebuild`/`run_offbox_rebuild`, `run_rm_container`/`run_onbox_rm_container`/`run_netbox_rm_container`/`run_offbox_rm_container` and `run_rm_image`/`run_onbox_rm_image`/`run_netbox_rm_image`/`run_offbox_rm_image`.
- Renamed `run_rm_container_any` → `run_rm_container` and `run_rm_image_any` → `run_rm_image` (container as first argument, matching the `run_container`/`run_recreate` convention). The cores, planners and all other executors are otherwise unchanged.

### [lib/git.sh](../../../lib/git.sh) — dead enumeration helper removed

- Deleted `list_submodule_git_dirs`; `absorb_submodules` continues to call `git submodule absorbgitdirs` directly.

### [MAP.gen.md](../../../MAP.gen.md)

- Updated the `talkbox.sh`, `lib/containers.sh` and `lib/git.sh` entries to describe the direct core dispatch, dropping the "nineteen `run_*` executor names" and `list_submodule_git_dirs` mentions.

## Test updates

Every retained test keeps its assertions unchanged; only call sites and (per the plan's allowance) descriptions referencing removed names were rewritten. Descriptions now name the core plus container (e.g. `run_netbox …` → `run_container netbox …`, `run_netbox_recontain …` → `run_recreate netbox no …`).

- [test/unit/containers.bats](../../../test/unit/containers.bats): the direct `run_onbox`/`run_recontain` call sites now invoke `run_container onbox`/`run_recreate onbox no` with empty `SRCS`/`DSTS` arrays declared in the setup (and local `srcs`/`dsts` in the pasta-ports test).
- [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats): `run_netbox`/`run_offbox` sites became `run_container netbox`/`run_container offbox`, and the recontain/rebuild sites (including the `run_${c}_${phase}` loop, now driven over the rebuild flags `no`/`yes`) became `run_recreate <container> <flag>`; the two nameref comments now name `run_container`.
- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats): the onbox recontain/rebuild sites became `run_recreate onbox no|yes` and all removal sites became `run_rm_container <container>`/`run_rm_image <container>`.
- [test/unit/git.bats](../../../test/unit/git.bats): the two `list_submodule_git_dirs` tests were removed — this edit is justified because those tests cover a function that existed only for them (referenced by nothing but the tests), so keeping them would be impossible without retaining dead production code; the submodule-absorption behaviour itself remains covered by the e2e suite and the `prepare_git_host` paths. No other test file was modified.

## Verification

- `make lint` and `make format`: clean over the modified files.
- `make test-unit`: total=315 pass=315 fail=0.
- `make test-e2e`: total=78 pass=78 fail=0 — the e2e suite and the dispatcher unit tests (which drive `talkbox.sh` as a subprocess over the logging podman shim) pin that the dispatch rewrite is externally invisible.
