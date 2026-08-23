# Phase 5: git merge and sync

Status: `SUCCESS`

This build implements [phase-5-merge-sync.gen.md](../plans/phase-5-merge-sync.gen.md), which completes `SPEC.md` by adding `custom_merge()` (DESCENDANT_CHECK, current-branch Cases 1-3 and other-branch `git branch -f`) and the `merge`/`sync` subcommands for `onbox`, `netbox` and `offbox` — `merge` fetches from the container gitdir volume via a bundle and applies `custom_merge <container> <branch>` on the host, while `sync` fetches from the `host` remote and applies `custom_merge host <branch>` inside the container's repository (via `podman exec` when the persistent container is running, or a temporary no-network container mounting the gitdir volume, worktree and `/host/git` otherwise). The provided verdict [phase-3-mount-write-assertion-contradiction.gen.md](../verdicts/phase-3-mount-write-assertion-contradiction.gen.md) records the mediation of an unrelated phase-3 test bug (rescoped a contradictory `:ro` assertion needle) and did not affect this phase.

## Overview

- `lib/merge.sh` (new) - self-contained, location-agnostic merge module defining `custom_merge()` and its helpers (`descendant_check`, `worktree_matches_tree`, `custom_merge_current`) using plain `git` against the current working directory; it is sourced by `lib/git.sh` (so `custom_merge()` remains defined via `lib/git.sh` per `SPEC.md`) and mounted read-only into every container at `/talkbox/lib/merge.sh`.
- `lib/git.sh` - sources `lib/merge.sh`; adds the `merge` action (`run_merge`: fetch from the container gitdir volume via `plan_fetch`/`execute_fetch_plan`, then `custom_merge <container> <branch>` per resolved branch) and the `sync` action (`run_sync`: resolve host branches, run `git fetch host` + `custom_merge host <branch>` inside the container via `run_sync_in_container`), with shared branch resolution (`resolve_branches`, defaulting to the host's current branch, `--all` over remote or host branches, and the `<branchname>` positional).
- `lib/options.sh` - parses the `merge`/`sync` verbs (kept distinct from `-c` commands), the `--all` flag and the optional `<branchname>` positional (`ONBOX_BRANCH`).
- `lib/containers.sh` - mounts `lib/merge.sh` read-only into `plan_onbox`/`plan_netbox`/`plan_offbox`; adds `container_running` and the `container_sync_cmd`/`run_sync_in_container` helpers which run the sync script inside a container's repository (via `podman exec --workdir /working/<base>` when running, or a temporary `--network=none` container mounting the gitdir volume, worktree, `/host/git` and the merge module otherwise).
- `talkbox.sh` - routes the `merge`/`sync` subcommands for `onbox` (via `onbox_action`) and `netbox`/`offbox` (via `sandbox_action`).

## Verification

- `make test-unit` - exit `0`; 149/149 tests passed (including the new `custom_merge` and `merge`/`sync` option-parsing unit tests).
- `make test-e2e` - exit `0`; 48/48 tests passed (including the new merge/sync end-to-end tests: container-commit fetch+merge, named-branch merge, `--all`, dirty-worktree warning, non-descendant refusal, and host-commit sync).
- `make lint` - exit `0`; ShellCheck clean on all modified scripts.
- `make format` - `shfmt` clean on all modified scripts.
