# Tests: Phase 21 onbox create/recontain ensure the base image exists

Red/green test pass for [Phase 21: onbox create/recontain ensure the base image exists](../plans/phase-21-onbox-base-image-probe.gen.md), which resolves [onbox-base-image-no-longer-probed](../issues/onbox-base-image-no-longer-probed.gen.md) by restructuring `resolve_inheritance` in `lib/containers.sh` so the `ensure_base_image` probe fires for every container whose resolved inheritance source is `base` — including the `onbox` short-circuit — so that `talkbox.sh onbox` and `talkbox.sh onbox --recontain` auto-build the shared base image from `image/Containerfile` when it is missing.

## New tests

### `test/unit/containers.bats`

- `run_onbox probes the base image and builds it when missing on the create path` — with the image present the `podman image exists <base>` probe fires once and no build runs; with `PODMAN_IMAGES` cleared the probe fires again and `podman build -t <base> -f $TALKBOX_ROOT/image/Containerfile $TALKBOX_ROOT/image` runs between the probe and `podman create`, with no `podman commit` (mirrors `run_netbox probes the base image and builds it when missing on the create path`). **Observed red:** the onbox short-circuit returns before any probe, so no `image exists` line is logged.
- The edited `run_onbox creates the container …, probing the base image` (see below) supplies the image-present half of the create-path coverage required by the plan ("the `image exists` probe fires when the image is present and no build runs").

### `test/unit/lifecycle.bats`

- `run_recontain probes the base image and builds it when missing before recreating the onbox container` — with the image present the probe fires and no build runs; with `PODMAN_IMAGES` cleared the probe fires and the build runs before `rm -f --volumes talkbox-proj.onbox` → `volume rm -f …onbox.gitdir` → `create` → `start`, with no `podman commit` (mirrors `run_offbox_recontain with no source container probes the base image and skips commit and build when it exists`). **Observed red:** no probe and no build occur on the recontain path.
- The edited `run_recontain removes, recreates and starts the onbox container …` (see below) supplies the image-present "probe fires exactly once before create" assertion.

### `test/e2e/onbox.bats`

- `onbox auto-builds the base image when it is missing` — prunes external containers on the e2e image, `podman rmi talkbox/base-e2e:latest`, verifies the image is gone, runs `talkbox.sh onbox -c --noninteractive true` through the usual `sdrun`/`mk_talkbox` harness, and asserts the command exits 0 and `podman image exists talkbox/base-e2e:latest` afterwards (the auto-build uses the swapped-in minimal Containerfile from `mk_talkbox`). **Observed red:** the onbox invocation fails (exit 1 at the status assertion) because `podman create` attempts a registry pull of the local-only image and dies with `Error: short-name "talkbox/base-e2e:latest" did not resolve to an alias and no unqualified-search registries are defined…`.

## Tests edited

- `test/unit/containers.bats` — `run_onbox creates the container with the workdir, userns and capability drops, probing no image` renamed to `…, probing the base image`: the zero `image exists` count assertion is replaced by "the `<base>` probe fires exactly once, before `podman create`, and no build runs while the image exists". Superseded per the plan ("the zero `image exists` count assertion (and title) no longer hold once the probe covers onbox; replace with assertions that the probe fires and no build runs when the image exists") and per `SPEC.md` §onbox ("This container is always created from the shared base image defined by `Containerfile`"). All other assertions (workdir, userns, cap-drops) are unchanged. **Observed red:** fails at the probe assertion against the current implementation.
- `test/unit/lifecycle.bats` — `run_recontain removes, recreates and starts the onbox container, running no nft, setup or user command`: the zero `image exists` count assertion is replaced by "the `<base>` probe fires exactly once, before `podman create`, and no build runs while the image exists". Superseded per the plan ("the zero `image exists` count assertion no longer holds; the probe now fires exactly once before create") and per `SPEC.md` §lifecycle management ("`onbox --recontain` recreates the `onbox` container and all of its associated volumes and then starts the container" — with the base image guaranteed to exist rather than assumed). All other assertions (rm/volume-rm/create/start/stop ordering, no volume create, no nft/setup/user exec) are unchanged. **Observed red:** fails at the probe assertion against the current implementation.

## Tests removed

None. The plan's "tests that must remain passing unchanged" list holds: every zero-probe assertion lives on a rebuild path guarded by `rebuild != yes` (`run_rebuild`, `run_netbox_rebuild`, `run_offbox_rebuild`, the "builds without probing" variants), `test/unit/dispatcher.bats` `talkbox.sh onbox --rm-container` has no create path, and the netbox/offbox commit-source tests (non-base source) plus the existing netbox/offbox base-fallback probe tests are untouched by the planned restructure of `resolve_inheritance`.

## Verification

- **Red (this pass, current implementation):** `make test-unit` → 305 total, 4 failures (the two edited tests and the two new unit tests); `make test-e2e` → 77 total, 1 failure (the new e2e test). All other tests pass.
- **Green (validated):** the planned single production change applied to a scratch copy of the tree (`resolve_inheritance` probing every `base` source outside an explicit rebuild, core files untouched) yields `make test-unit` → 305/305 pass and `make test-e2e` → 77/77 pass, confirming the new tests fail for the planned functionality and pass once it is implemented.
