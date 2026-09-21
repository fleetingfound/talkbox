# Phase 16a: Prune external working containers before `--rm-image`

Status: `SUCCESS`

This build implements [phase-16a-rm-image-prune-external-working-containers.gen.md](../plans/phase-16a-rm-image-prune-external-working-containers.gen.md): `onbox --rm-image`, `netbox --rm-image` and `offbox --rm-image` now prune buildah external working containers referencing the base image before `podman rmi`, so the `image_in_use` guard and `podman rmi` agree on what counts as "in use" and the unforced `rmi` succeeds, honouring the SPEC safety contract at [SPEC.md](SPEC.md) line 253. It resolves the issue [--rm-image blocked by external working containers](../issues/rm-image-blocked-by-external-working-containers.gen.md). No verdict document was provided and no dispute was required.

## Overview

- `lib/containers.sh` - new `prune_external_image_containers <image>` helper which queries `podman ps -a --external --filter "ancestor=<image>" --format '{{.ID}}'` and force-removes each returned ID via `podman rm -f`; it silently succeeds when no external working containers match.
- `lib/containers.sh` - `run_rm_image`, `run_netbox_rm_image` and `run_offbox_rm_image` each call the helper after the `image_in_use` guard passes and after the existing `container_exists ... && podman rm -f --volumes` cleanup, before `execute_plan` runs `podman rmi`. `image_in_use` itself is unchanged, preserving its semantics (refuse removal when real user-created containers use the base image).

## Pending user commit

The plan (L36) asks `teardown_talkbox` in `test/e2e/helpers.bash` to gain a best-effort `podman rm -f --external` step so buildah artifacts do not accumulate across test suites. The environment's permission rules deny edits under `test/*` to this agent (matching the invariant that the test harness is not edited), so the change is not applied here and is left for the user; it is test-harness hygiene only and is not required for the `--rm-image` fix, since the core prune logic in `lib/containers.sh` makes the affected tests pass regardless.

## Verification

- `make test-unit` - exit `0`; 267/267 tests passed, including the five new `prune_external_image_containers` / `run_*_rm_image` unit tests.
- `make test-e2e` - exit `0`; 76/76 tests passed with 0 skipped, including the regression target `netbox --rm-image removes the base image`.
- ShellCheck and `shfmt` are clean on the modified shell files (only pre-existing `SC1091` source-not-followed notices remain in `lib/containers.sh`).
