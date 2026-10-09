# Choices

## Implementation design choices

- [x] [Module Structure](module-structure.gen.md) - how to split `talkbox.sh` logic across `lib/`.
- [x] [Volume Population Strategy](volume-population.gen.md) - how read-write volumes and root filesystem inheritance are populated.
- [x] [Test Modularization](test-modularization.gen.md) - split of unit vs end-to-end test coverage.
- [x] [Planner-vs-executor project-dotfiles existence handling](planner-dotfiles-existence.gen.md) - whether the project-dotfiles existence check lives in the planner or the executor.

## Planner/executor divergence resolution

- [x] [Planner/executor resolution strategy](planner-executor-resolution.gen.md) - whether to wire the executors to their `plan_*` counterparts, extend the plan model for the conditional run path, or delete the unused plan functions.

## Phase 5 design choices

- [x] [custom_merge availability inside and outside the container](custom-merge-availability.gen.md) - how `custom_merge()` reaches both the host (`merge`) and the container's git repository (`sync`).

## Scaffold refactor choices (Phase 1c)

- [x] [Scaffold refactor scope](scaffold-refactor-scope.gen.md) - which of the review's recommendations to address in the scaffold-refactor phase before Phase 2.
- [x] [Planner array-population mechanism](planner-array-mechanism.gen.md) - nameref-populating planner vs NUL-delimited stdout for the array-based planner interface.

## Test-quality fixes

- [x] [E2e --port TOCTOU fix](e2e-port-toctou-fix.gen.md) - how to eliminate the probe-then-rebind race in `free_host_port` (Python port-0 server, FD passing, retry loop, socat, or banner parsing).

## Git transport review choices (Phase 5 follow-up)

- [x] [Case 1 untracked-files handling](case1-untracked-files.gen.md) - whether `custom_merge_current` Case 1 should allow untracked files or keep treating them as dirty.
- [x] [merge/sync failure behaviour on --all](merge-sync-failure-behaviour.gen.md) - whether `sync --all` should continue on branch failure like `merge --all`, or whether both should stop on first failure.

## GPU support choices

- [x] [GPU flag threading](gpu-flag-threading.gen.md) - how the parsed `--gpu` flag reaches the `plan_onbox`/`plan_netbox`/`plan_offbox` planners.

## Lifecycle volume cleanup choices

- [x] [Write-volume discovery for `--rm-container`](rm-container-write-volume-discovery.gen.md) - how `plan_netbox_rm_container`/`plan_offbox_rm_container` obtain the per-dest write volume names to remove (thread write-mount dests, glob-list by name pattern, or inspect the container's mounts).

## Git identity propagation (Phase 9b)

- [x] [Git identity propagation into containers](git-identity-propagation.gen.md) - the mechanism by which the host's `user.name`/`user.email` reach the container's git config (env vars + entrypoint global config write, `GIT_AUTHOR_*` env vars only, or entrypoint write to repo local config during init).

## Repository-review follow-up choices

- [x] [`execute_fetch_plan` boundary mechanism](execute-fetch-plan-boundary.gen.md) - how to replace the brittle `git fetch` token-sniffing splitter in `execute_fetch_plan` (two-array output, explicit delimiter, or reuse `execute_plan`).
- [x] [`podman stop` grace period](podman-stop-grace-period.gen.md) - what stop grace period to use for the nine `podman stop -t 1` call sites, and whether to extract a named constant.

## Container exit hang (PID 1 signal handling)

- [x] [PID 1 signal handling for persistent containers](pid1-signal-handling.gen.md) - how to give the `onbox`/`netbox`/`offbox` persistent containers a PID 1 that honours `SIGTERM` so `podman stop` returns promptly (`--init`, entrypoint trap, or a signal-handling command loop).

## Command-prompt host segment (Phase 10b)

- [x] [Command-prompt host segment (`<project-slug>.<container-type>`)](prompt-host-segment.gen.md) - how `<project-slug>` and `<container-type>` reach the container's interactive prompt and where the `<slug>.<container>` string is assembled (two env vars read by `.bashrc`, a single combined env var, or entrypoint-assembled).

## IP deny/allow lists

- [x] [IP deny/allow enforcement mechanism](ip-deny-allow-enforcement.gen.md) - how the deny/allow IP and CIDR lists are enforced for onbox/netbox (nftables in the container netns via nsenter, iptables in the netns, host-side nftables, or a pre-created managed netns).
- [x] [IP deny/allow module structure](ip-deny-allow-module.gen.md) - where the deny/allow parsing, effective-set computation and rule application live (new `lib/netfilter.sh`, extend/rename `lib/ports.sh`, or inline in `lib/containers.sh`).

## IPv6 deny/allow CIDR carving

- [x] [IPv6 deny/allow CIDR range carving approach](ipv6-deny-allow-carving-approach.gen.md) - how to perform IPv6 range subtraction in `deny_allow_subtract` given Bash cannot hold a 128-bit integer natively (pure Bash four-32-bit words, delegate to python3, minimum `::1` special-case, or move the set difference into nft).

## nft deny install fail-hard behaviour

- [x] [nft deny failure scope](nft-deny-failure-scope.gen.md) - which failure conditions in `install_nft_deny` abort the container start (nft pipeline error only, or also the PID-lookup failure).
- [x] [nft deny error surfacing](nft-deny-error-surfacing.gen.md) - whether the underlying `nft`/`nsenter` stderr is surfaced to the user on failure.
- [x] [nft deny failure escape hatch](nft-deny-failure-escape-hatch.gen.md) - whether to provide an env-var opt-out restoring warn-and-continue behaviour.
- [x] [nft deny failure container cleanup](nft-deny-failure-container-cleanup.gen.md) - whether to stop/remove the already-started container before raising the error.
- [x] [nft PATH resolution](nft-path-resolution.gen.md) - how to auto-handle `nft` being installed at `/usr/sbin` but off the non-root PATH (PATH augmentation, absolute-path resolution, or diagnostic-only).

## Entrypoint readiness synchronization

- [x] [Entrypoint readiness synchronization mechanism](entrypoint-readiness-sync.gen.md) - how the `run_onbox`/`run_netbox`/`run_offbox` executors wait for the entrypoint to finish its start-up work before running `podman exec` (tmpfs sentinel, filesystem sentinel with remove-at-start, podman healthcheck, or moving setup into an exec step).

## Post-nft entrypoint setup ordering

- [x] [Post-nft entrypoint setup invocation mechanism](post-nft-setup-invocation.gen.md) - how the entrypoint setup body is moved out of the image ENTRYPOINT into a post-nft `podman exec` for persistent containers (override `--entrypoint` with a no-op command, extract a separate `setup.sh`, or add a `--setup-only` mode to `entrypoint.sh`).

## Inline comments in config files

- [x] [Inline-comment scope](inline-comment-scope.gen.md) - whether inline `#` comments are supported only in `deny.ip`/`allow.ip` or uniformly across all config files (`read.mounts`, `write.mounts`, `ports`, `deny.ip`, `allow.ip`).

## `--rm-image` blocked by external working containers

- [x] [External working container handling for `--rm-image`](external-working-container-handling.gen.md) - whether to prune external buildah working containers before `rmi`, make `image_in_use` detect them, or prune them after every `podman build`.

## E2e shared-image inter-test coupling elimination

- [x] [E2e shared-image inter-test coupling elimination](e2e-shared-image-coupling-elimination.gen.md) - how to eliminate (not mask) the shared `talkbox/base:latest` image coupling between `deny-allow.bats` (rebuilds) and `netbox-offbox.bats` (destroys): a shared `ensure_base_image_e2e` helper called by each e2e test's setup, making the image-existence precondition explicit per-test.

## ASCII art on container startup

- [x] [ASCII art display location](ascii-art-display-location.gen.md) - whether the art is printed by the host-side executor before `podman exec` or from inside the container by `.bashrc`.
- [x] [ASCII art file format and storage](ascii-art-file-format.gen.md) - where the art files are stored in the repo and how ANSI SGR escape sequences are represented in those files.

## Minimal test Containerfile

- [x] [Test base-image tag isolation](minimal-test-image-tag-isolation.gen.md) - how the e2e suite targets a base image tag distinct from the production `talkbox/base:latest` (env-var override in `base_image_name()`, shared production tag, or rewriting the copied `lib/naming.sh`).
- [x] [Minimal test Containerfile placement and selection](minimal-test-containerfile-placement.gen.md) - where the minimal Containerfile lives and how every test-reachable build path (`ensure_base_image`, `--rebuild` planners) comes to use it.
- [x] [Minimal test image content](minimal-test-image-content.gen.md) - what the minimal test image contains (Debian-slim with git/curl/ca-certificates, a multi-stage target in the production Containerfile, or an Alpine base).

## `lib/containers.sh` consolidation (Phase 19)

- [x] [Consolidation boundary and unit-test surface](containers-consolidation-boundary.gen.md) - which interfaces survive the Phase 19 consolidation (the `run_*` executors as delegates over unified cores with executor-level unit tests, or full parameterization with CLI-level unit tests). Selected: executor-surface preservation.

- [x] [Podman shim factory interface](shim-factory-interface.gen.md) - how the ~14 inline podman shims, the shadowed `make_podman_shim` in `network.bats` and `mk_gpu_shim` are consolidated (extend the env-driven shared shim, a flag-driven factory, or a minimal rename). Selected: extend the env-driven shared shim, with delegation to real podman treated separately via a dedicated e2e-side logging-delegate helper.
- [x] [E2e setup/teardown parameterisation mechanism](e2e-setup-teardown-mechanism.gen.md) - how the seven e2e files' setup/teardown boilerplate is parameterised (shared pair plus registration helpers, fully declarative pair, or shared helpers only). Selected: shared pair plus registration helpers.
- [x] [HTTP readiness wait placement](http-readiness-wait-placement.gen.md) - whether the HTTP readiness poll becomes a standalone `wait_for_http` helper or is folded into `start_host_http_server`. Selected: standalone `wait_for_http`.
- [x] [E2e run wrapper mechanism](e2e-run-wrapper-mechanism.gen.md) - how the hand-rolled `sdrun bash -c 'cd …'` sites are routed through shared helpers (extend `run_talkbox` with a PATH-prepend plus a symlink helper, caller-side PATH prefixing, or no change). Selected: extend `run_talkbox` plus a symlink helper.

## Duplication-review resolution choices (Phase 20)

- [x] [Naming dispatch consolidation scope](naming-dispatch-consolidation.gen.md) - whether the per-container naming one-liners and `*_of` dispatch layer are replaced by a parametric resource-name function, or left as the documented dispatch surface. Selected: defer.
- [x] [Write-mount parse-once mechanism](write-mount-parse-once.gen.md) - how `sandbox_action`'s double parse of the write mounts is eliminated (signature change of `mount_volume_args` to accept precomputed entries, a parallel from-entries variant, or no change). Selected: accept precomputed entries.
- [x] [`run_fetch` git-history guard reuse](run-fetch-git-history-probe.gen.md) - whether `run_fetch` reuses `require_git_history` directly (behaviour change) or a shared non-fatal probe preserving current semantics. Selected: shared non-fatal probe.

## Unresolved-issue resolution choices

- [x] [Leftover e2e `sdrun` units from an interrupted suite run](e2e-leftover-unit-drain.gen.md) - how the harness prevents leftover nested `systemd-run` units from a killed suite run from racing the immediately following run (stop-propagation so nested units die with the parent, preflight stop, preflight wait, or documentation only). Selected: die with parent via `StopPropagatedFrom=`.
- [x] [Write-volume discovery for `--rm-container` (revisited)](rm-container-write-volume-discovery-revisit.gen.md) - how `plan_container_volumes_rm` obtains the write volumes to remove, replacing the current-invocation dest-list derivation (name-pattern listing, container-mount inspection, or a persistent record). Selected: container-mount inspection.
- [x] [Placement of the write-mount folder validation](write-mount-validation-placement.gen.md) - where the check that write-mount sources are existing directories lives (inside `mount_entries`, in the dispatcher after parsing, or in the container planners). Selected: inside `mount_entries`, mode-conditional.
- [x] [Cleanup of auto-created volumes when container creation fails](populate-failure-volume-cleanup.gen.md) - how a failed populate stops the auto-created named volumes from leaking (executor rollback, explicit volume pre-creation, or validation only). Selected: executor rollback.

## Container consolidation choices (Phase 25)

- [x] [onbox `--recontain` start-time steps](onbox-recontain-start-steps.gen.md) - how the onbox recontain/rebuild skip of nft and `setup.sh` is resolved (align with `run_container`, formalize the skip as config, or skip for all containers). Selected: align with `run_container`.
- [x] [Per-container configuration mechanism](container-config-mechanism.gen.md) - how the per-container configuration record is represented and where it lives (case-based lookup module, associative-array table, or per-field accessors). Selected: case-based lookup module.
- [x] [Consolidation scope](container-consolidation-scope.gen.md) - whether all ~12 container-conditional branch points become configuration, or 2-3 readable cases (notably `inherit_source`) are retained. Selected: full config-driven.
- [x] [Post-consolidation naming interface](container-naming-interface.gen.md) - what replaces the 9 naming one-liners and the 4 `*_of` dispatchers (genericized `*_of` dispatchers, one parametric resource-name helper, or no change). Selected: genericized `*_of` dispatchers.
