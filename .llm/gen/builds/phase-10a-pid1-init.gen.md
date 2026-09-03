# Build: Phase 10a — `--init` for persistent containers (PID 1 signal handling)

Status: **SUCCESS**

Implemented [Phase 10a](.llm/gen/plans/phase-10a-pid1-init.gen.md): the three persistent-container planners `plan_onbox`, `plan_netbox` and `plan_offbox` in [lib/containers.sh](../../../lib/containers.sh) now append the literal `--init` flag alongside their `--userns`/`--network`/`--cap-drop` options, ahead of the image name and the `sleep infinity` command, so `podman create` injects `catatonit` as PID 1 (which reaps zombies and forwards `SIGTERM` to `sleep`). Because the `--recontain`/`--rebuild` lifecycle planners and the `run_*`/`create_*` executors consume these argument lists unchanged, the flag propagates to every persistent-container create path, while the one-shot `plan_volume_populate` containers remain without `--init`. This resolves the issue [PID 1 (`sleep infinity`) ignores `SIGTERM`](.llm/gen/issues/pid1-sleep-ignores-sigterm.gen.md) per the selected design in [PID 1 signal handling for persistent containers](.llm/gen/choices/pid1-signal-handling.gen.md) (Option A — `--init` with `catatonit`); no image or entrypoint changes were required.

Verified: `make test-unit` passes 198/198; `make test-e2e` passes 67/67.
