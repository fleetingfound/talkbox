# Tests: Phase 20f convergence of create_sandbox and plan_recreate

Pinning-test pass for [phase-20f-create-recreate-convergence](../plans/phase-20f-create-recreate-convergence.gen.md), which plans to extract a shared inheritance-resolution helper and a shared populate→gitdir-volume→create plan assembler from the near-identical heads and tails of `create_sandbox` and `run_recreate`/`plan_recreate` in `lib/containers.sh`, with every emitted podman command sequence unchanged. These tests close the gaps between what the create path and the recreate path emit where the planned shared helpers will guarantee their agreement; no core files were modified and every new and surviving test passes against the current implementation.

## New tests

### test/unit/containers.bats

Two tests driving the onbox create path (`run_onbox` → `create_sandbox`) and the recreate path (`run_recontain` → `run_recreate` → `plan_recreate`) over the logging podman shim:

1. `run_onbox create line is byte-identical to the run_recontain recreate line` — the `podman create` argument list assembled by the create path equals the one assembled by the recreate path token for token, pinning the shared `plan_container` create-argument assembly across both entry points.
2. `run_onbox omits the gitdir volume create when the gitdir volume already exists` — the create-path gitdir-volume assembly (the future shared `plan_gitdir_volume` tail) emits no `podman volume create` when the gitdir volume exists while the create line still mounts it, complementing the existing missing-volume test.

### test/unit/netbox-offbox.bats

Seven tests covering the netbox/offbox create path, the recreate path and their convergence:

3. `run_netbox create path creates the gitdir volume after populate and before create` — pins the populate → gitdir-volume-create → create ordering of the create-path tail; previously only `populate < create` and `volume create < create` were pinned separately, not the populate/gitdir edge the shared assembler fixes.
4. `run_netbox create path omits the gitdir volume create when the gitdir volume already exists` — the netbox counterpart of test 2.
5. `run_netbox probes the base image and builds it when missing on the create path` — with the base image present the create path probes `podman image exists` and builds nothing; with it missing the probe is followed by `podman build -t <base> -f <Containerfile>` before populate and create, and no commit is issued. This pins the create-path half of the base-image ensure/build decision the planned inheritance-resolution helper will own (only the recreate-path half was pinned before).
6. `run_netbox create line is byte-identical to the recontain recreate line from the base image` — create-argument convergence for the base-source resolution.
7. `run_netbox create line is byte-identical to the recontain recreate line when inheriting from onbox` — create-argument convergence for the commit-from-onbox resolution, with both create lines using `<project>.netbox.root`.
8. `run_offbox create line is byte-identical to the recontain recreate line when inheriting from netbox` — create-argument convergence for the commit-from-netbox resolution, with both create lines using `<project>.offbox.root`.
9. `run_netbox and run_netbox_recontain build identical create lines under TALKBOX_FRESH and TALKBOX_INHERIT` — under `TALKBOX_FRESH=yes` both paths skip the commit and use the base image; under `TALKBOX_INHERIT=offbox` both paths commit the offbox container into `<project>.netbox.root`; the create lines match the create path's in both scenarios, pinning the `--fresh`/`--inherit` branches of the resolution head on the recreate path.

### test/unit/lifecycle.bats

Two tests pinning the recreate-path base-image ensure/build decision:

10. `run_offbox_recontain with no source container probes the base image and skips commit and build when it exists` — with no source containers the offbox recreate path probes `podman image exists`, commits nothing, builds nothing, creates from the base image, and orders rm → populate → gitdir-volume create → create → start (the netbox counterpart was already pinned; this adds the offbox container to the shared decision).
11. `run_netbox_rebuild with no source container builds without probing or committing` — with rebuild=yes and no source containers the recreate path emits the explicit `podman build` first with no `image exists` probe and no commit, then rm → populate → gitdir-volume create → create (base image) → start, pinning the rebuild branch of the ensure/build decision for the base-source case (only the commit-source rebuild case was pinned before).

## Tests edited

None. The executor-level tests in `test/unit/containers.bats`, `test/unit/netbox-offbox.bats` and `test/unit/lifecycle.bats` already pin the create, recontain, rebuild, inheritance and volume-populate command sequences and all keep passing unchanged, as the plan's tests section requires.

## Tests removed

None. The plan states "No existing tests are superseded or removed — no tested internal interface is dropped", and no tested internal interface disappears: `create_sandbox`, `plan_recreate`, `plan_container`, the `plan_*_populate` planners and the `run_*` executors keep their signatures and dispatch surface.

## Verification

Against the unmodified implementation: `make test-unit` 298/298 (287 existing + 11 new), `make test-e2e` 76/76, `make lint` and `make format` all pass.
