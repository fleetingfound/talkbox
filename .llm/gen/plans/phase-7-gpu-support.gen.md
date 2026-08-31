# Plan: Phase 7 — GPU support (`--gpu` flag)

#flow/redgreen #model/default

## Specification scope

Implements the **gpu support** section of [SPEC.md](../../../SPEC.md) (lines 347-355): when the flag `--gpu` is given to any of `onbox`, `netbox` or `offbox`, any available Nvidia GPUs from the host are made available in the created container by appending `--device nvidia.com/gpu=all` and `--group-add keep-groups` to the `podman create` invocation.

No other aspect of `SPEC.md` / `SPEC.gen.md` is altered. (Note: the spec text at line 349 contains a typo `openbox`; this is read as `onbox` per the rest of the specification and the fixed README.)

The design follows [GPU flag threading](../choices/gpu-flag-threading.gen.md) — Option B: the parsed `TALKBOX_GPU` global is read directly inside the three planners.

## To be implemented

- Parse `--gpu` in [lib/options.sh](../../../lib/options.sh): set `TALKBOX_GPU=yes` (default `no`).
- In [lib/containers.sh](../../../lib/containers.sh), inside `plan_onbox`, `plan_netbox` and `plan_offbox`, when `TALKBOX_GPU == yes`, append the two podman options `--device nvidia.com/gpu=all` and `--group-add keep-groups` to the create-argument list. These should be appended alongside the other top-level `podman create` flags (i.e. near `--userns`/`--network`/`--cap-drop`), before the `-v` mount list, so they are visible in all create paths.

Because the three planners are the single source of truth for create arguments, the default-create (`run_onbox`/`run_netbox`/`run_offbox`), recontain and rebuild paths all inherit GPU support automatically with no further changes.

## To be deferred

- GPU access for the temporary no-network helper containers used by `plan_volume_populate` and the `container_sync_cmd` fallback `podman run`. These perform only file copies or git operations and do not benefit from a GPU; the spec scopes GPU access to the `onbox`/`netbox`/`offbox` containers themselves.
- Any GPU-availability detection or warning when `--gpu` is passed on a host without an Nvidia GPU. The spec specifies only that the two options be passed to `podman`; podman/host behaviour when no GPU is present is out of scope.

## External-facing functionality

`onbox --gpu`, `netbox --gpu` and `offbox --gpu` create their respective containers with Nvidia GPU access enabled. The flag combines with all existing flags and verbs (`-c`, `--fresh`, `--inherit`, `--recontain`, `--rebuild`, etc.). Without `--gpu`, behaviour is unchanged.

## Files to be created

- None.

## Files to read during implementation

- [lib/options.sh](../../../lib/options.sh) — add `--gpu` parsing and the `TALKBOX_GPU` default.
- [lib/containers.sh](../../../lib/containers.sh) — `plan_onbox`, `plan_netbox`, `plan_offbox` (append GPU options).
- [talkbox.sh](../../../talkbox.sh) — confirm no changes are required (the global is read by the planners, not the dispatchers).

## Key internal interfaces

- `TALKBOX_GPU` — new scalar global (default `no`) set by `parse_talkbox_options` and read by `plan_onbox`/`plan_netbox`/`plan_offbox`. Follows the same pattern as `TALKBOX_FRESH` and `TALKBOX_INHERIT`.

## Tests

Per `SPEC.md` (testing, line 394): **do not write tests for GPU usage, since a GPU may not be available on all systems where tests are run.**

- **Unit tests:** add a unit test asserting that `parse_talkbox_options` sets `TALKBOX_GPU=yes` when `--gpu` is present and `no` when absent. This verifies the parser without invoking `podman` or requiring a GPU.
- **End-to-end tests:** add an e2e test (noninteractive, `-c`) asserting that `onbox --gpu` (and analogously `netbox --gpu`/`offbox --gpu`) successfully creates and runs a container on a GPU-less host — i.e. podman accepts the `--device`/`--group-add` options without error even when no GPU device is present. The test must not assert that a GPU is actually exposed inside the container. Run the full e2e suite to confirm no regressions in the non-`--gpu` paths.
