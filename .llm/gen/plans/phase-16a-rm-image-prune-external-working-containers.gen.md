# Plan: Phase 16a — Prune external working containers before `--rm-image`

#flow/redgreen #model/default

## Specification scope

Implements the `--rm-image` safety contract from [SPEC.md](../../../SPEC.md) line 253 ("removes the base image, but will not remove the image if it is being used by other containers") by ensuring that the `image_in_use` guard and `podman rmi` agree on what counts as "in use." Resolves the issue [--rm-image blocked by external working containers](../issues/rm-image-blocked-by-external-working-containers.gen.md).

No aspect of `SPEC.md` / `SPEC.gen.md` is altered. The external buildah working containers created by `podman build` are transient build artifacts, not "containers using the image" in the SPEC's sense, so pruning them before `rmi` preserves the safety contract.

## To be deferred

- Pruning external working containers after every `podman build` in `ensure_base_image` (Option 3 in the [choice document](../choices/external-working-container-handling.gen.md)). This would prevent accumulation at the source but is not needed for correctness of `--rm-image`; it can be added later if accumulation becomes a concern in other code paths.
- Factoring the three near-identical `run_rm_image` / `run_netbox_rm_image` / `run_offbox_rm_image` functions into a shared core. The minimal targeted change is to add the prune call to each; a deduplication refactor is a separate concern.

## External-facing functionality

`onbox --rm-image`, `netbox --rm-image`, and `offbox --rm-image` now succeed even when buildah external working containers (created by prior `podman build` calls) reference the base image. The `image_in_use` guard continues to refuse removal when *real* user-created containers use the base image, honouring the SPEC's safety contract.

## Files to be created

- None.

## Files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — `plan_rm_image` (lines 148–154), `image_in_use` (lines 204–214), `run_rm_image` (lines 274–285), `run_netbox_rm_image` (lines 833–844), `run_offbox_rm_image` (lines 846–857).
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — `teardown_talkbox` (lines 51–65).
- [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) — the `netbox --rm-image removes the base image` test (lines 156–165).
- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) — existing `plan_rm_image` unit tests (lines 168–182, 359–373).

## Key internal interfaces

- A new helper function in [lib/containers.sh](../../../lib/containers.sh) (e.g. `prune_external_image_containers <image>`) that queries `podman ps -a --external --filter "ancestor=<image>" --format '{{.ID}}'` and force-removes each resulting external working container ID via `podman rm -f`. The helper is best-effort: it silently succeeds when no external containers match.
- Each of `run_rm_image`, `run_netbox_rm_image`, and `run_offbox_rm_image` calls the new helper after the `image_in_use` guard passes and before `execute_plan` runs `podman rmi`. This placement is consistent with the existing `container_exists "$ctr" && podman rm -f --volumes "$ctr"` cleanup that already precedes the plan execution in these functions.
- `image_in_use` is **not** modified — its semantics (refuse removal when real containers reference the image) remain correct.
- `teardown_talkbox` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) gains a best-effort `podman rm -f --external` step (or a call to the same helper scoped to the base image) so buildah artifacts from prior test suites do not accumulate and block `--rm-image` tests.

## Tests

Requires tests:

- **Unit tests** (in `test/unit/lifecycle.bats` or a suitably placed unit file): verify the new prune helper queries `podman ps -a --external --filter ancestor=<image>` and issues `podman rm -f` for each returned ID. These will need the existing podman-stub/mock pattern used by other unit tests in that file.
- **End-to-end test**: the existing `netbox --rm-image removes the base image` test in [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) (lines 156–165) already captures the desired behaviour and is currently failing. After the fix it should pass. No new e2e test is required; the existing one is the regression target.
