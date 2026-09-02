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
