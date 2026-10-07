# Phase 21: onbox create/recontain ensure the base image exists

#flow/redgreen #model/default

## issue

Resolves [Onbox create/recontain no longer ensure the base image exists](../../issues/onbox-base-image-no-longer-probed.gen.md).

Phase 20e dropped the dispatcher's explicit `ensure_base_image` calls from the onbox branches on the belief that `create_sandbox` and `run_recreate` already probe internally for a base source. That premise is false: in `resolve_inheritance` the probe sits in the non-onbox `else` arm, so for `onbox` (whose inheritance source is unconditionally `base`) no probe runs. After the refactor, `talkbox.sh onbox` and `talkbox.sh onbox --recontain` fail with a raw registry-pull error when the base image is missing, instead of auto-building it from `image/Containerfile`.

## specification aspects

Implements from `SPEC.md`:

- "onbox" container section: the onbox container "is always created from the shared base image defined by `Containerfile`" — the create and recontain paths must guarantee that image exists locally, building it from `image/Containerfile` when missing.
- "image and container management": `onbox --recontain` recreates the container; the implicit precondition that the base image exists must be ensured rather than assumed.

Deferred: nothing.

## external-facing functionality

- `talkbox.sh onbox` (default verb) and `talkbox.sh onbox --recontain` auto-build the shared base image (default `talkbox/base:latest`, honouring `TALKBOX_BASE_IMAGE`) from `image/Containerfile` when it does not exist, restoring the pre-Phase-20e behaviour.
- When the image already exists, behaviour is unchanged apart from one additional idempotent `podman image exists` probe before container creation.
- `onbox --rebuild` is unchanged: it still builds explicitly via `plan_recreate` and performs no probe.
- netbox/offbox base-fallback create/recontain paths are unchanged (they already probe); non-base (commit) inheritance paths are unchanged (no probe).

## implementation

A single production change in `lib/containers.sh`:

- Restructure `resolve_inheritance` so the `ensure_base_image` probe fires for every container whose resolved inheritance source is `base` — including the `onbox` short-circuit — rather than only in the non-onbox arm. The probe remains guarded by the rebuild flag (`create_sandbox` passes `no`; `run_recreate` passes the verb's flag) so explicit rebuild paths, which plan the build in `plan_recreate`, still do not probe.

No dispatcher changes: `talkbox.sh`'s unified `container_action` from Phase 20e stays as-is; the probe belongs in the executor layer, consistent with the Phase 19/20 consolidation.

## files to create or modify

- `lib/containers.sh` — modify `resolve_inheritance` (extend the probe to the onbox/base path).
- `test/unit/containers.bats` — supersede the onbox create-path "probing no image" pin; add onbox probe/build coverage.
- `test/unit/lifecycle.bats` — supersede the onbox recontain zero-probe pin; add onbox recontain build-when-missing coverage.
- `test/e2e/onbox.bats` — add a regression test covering the auto-build on a missing image end-to-end.
- `MAP.gen.md` — update the `lib/containers.sh` entry if its description of the probe's scope changes.

## files to read during implementation

- `.llm/gen/issues/onbox-base-image-no-longer-probed.gen.md`
- `lib/containers.sh` (`resolve_inheritance`, `create_sandbox`, `run_recreate`, `ensure_base_image`, `plan_recreate`)
- `test/unit/containers.bats`, `test/unit/lifecycle.bats`, `test/unit/netbox-offbox.bats` (the "run_netbox probes the base image and builds it when missing on the create path" test is the template for the onbox variant)
- `test/e2e/onbox.bats`, `test/e2e/helpers.bash` (`ensure_base_image_e2e`, `mk_talkbox`, `E2E_BASE_IMAGE`)

## tests to be superseded

- `test/unit/containers.bats`: "run_onbox creates the container with the workdir, userns and capability drops, probing no image" — the zero `image exists` count assertion (and title) no longer hold once the probe covers onbox; replace with assertions that the probe fires and no build runs when the image exists.
- `test/unit/lifecycle.bats`: "run_recontain removes, recreates and starts the onbox container, running no nft, setup or user command" — the zero `image exists` count assertion no longer holds; the probe now fires exactly once before create.

Tests that must remain passing unchanged:

- all rebuild tests asserting zero probes (`run_rebuild`, `run_netbox_rebuild`, `run_offbox_rebuild`, and the "builds without probing" variants) — the `rebuild != yes` guard keeps these at zero;
- `test/unit/dispatcher.bats` `onbox --rm-container` (no create path, no probe);
- netbox/offbox commit-source tests (non-base source, no probe) and the existing netbox/offbox base-fallback probe tests.

## test coverage

Unit tests (podman shim):

- onbox create path: the `image exists` probe fires when the image is present and no build runs; with the image absent, a build from `$TALKBOX_ROOT/image/Containerfile` fires before `podman create` (mirror of the existing netbox create-path test).
- onbox recontain path: the probe fires before create; with the image absent, the build fires on the recontain path (mirror of the existing offbox no-source recontain test).

End-to-end tests:

- `test/e2e/onbox.bats`: remove the e2e base image (`talkbox/base-e2e:latest`), run `onbox -c --noninteractive true` via the usual `sdrun`/`mk_talkbox` harness, and assert the command succeeds and the image exists afterwards (auto-built from the swapped-in minimal Containerfile).
