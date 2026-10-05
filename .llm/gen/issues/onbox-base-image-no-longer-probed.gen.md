# Onbox create/recontain no longer ensure the base image exists

Phase 20e dropped the explicit `ensure_base_image` calls from the onbox branches of the dispatcher, as instructed by its plan, which justifies the drop by claiming `create_sandbox` and `run_recreate` "already perform the same idempotent probe internally for a base source". That premise is false for the onbox branch: in both functions the `ensure_base_image` probe sits inside the non-onbox `else` arm (`create_sandbox` and `run_recreate` in `lib/containers.sh`), so for `container == onbox` (where `source` is unconditionally `base`) no probe runs. The executor-level pinning tests deliberately pin this (`run_onbox ... probing no image`, `run_recontain ... image exists count 0`), so extending the probe to the onbox/base path inside `lib/containers.sh` is not possible without disputing those tests, and was not done.

Consequence: after this refactor, `talkbox.sh onbox` (default verb) and `talkbox.sh onbox --recontain` no longer build `talkbox/base:latest` when it is missing. `podman create` then attempts a registry pull of the local-only image and fails with a raw podman error; previously the dispatcher auto-built the image from `image/Containerfile`. The same paths with the image present (all tests and the documented e2e workflow) behave identically. `onbox --rebuild` is unaffected because `plan_recreate` plans the build explicitly.

Files causing the issue:

- `talkbox.sh` (`container_action` — the dropped `ensure_base_image` calls)
- `lib/containers.sh` (`create_sandbox`, `run_recreate` — the base-image probes cover only the netbox/offbox `source == base` arm)

Suggested fix: move the `ensure_base_image` probe in `create_sandbox` and `run_recreate` out of the non-onbox `else` arm so it fires for every container whose resolved inheritance source is `base` (guarded by `rebuild != yes` in `run_recreate`, as today), then update the two executor-level pinning tests that assert a zero `image exists` count on the onbox create/recontain paths.
