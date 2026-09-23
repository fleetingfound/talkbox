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
