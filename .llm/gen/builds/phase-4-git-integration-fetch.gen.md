# Phase 4: git integration (onbox/netbox/offbox) and fetch

Status: `SUCCESS`

This build implements [phase-4-git-integration-fetch.gen.md](../plans/phase-4-git-integration-fetch.gen.md), which adds the git-specific mounts and in-container wiring to all three containers (`onbox`, `netbox`, `offbox`): the per-container gitdir volume, the read-only host git folder, the `host` remote, worktree configuration, submodule absorption on the host, refusal to mount when the host git directory lies outside `<project>`, and the `fetch` git-transport subcommand that moves committed changes from a container's gitdir volume into the host repository via a git bundle.

No verdict document was provided for this phase, and no new dispute or issue documents were created.

## Overview

- `lib/git.sh` (new) - host-side git helpers: `git_tracked`/`resolve_git_dir`/`classify_git_dir` (pure inside/outside/none classification of the resolved host git directory), `list_submodule_git_dirs` (submodule absorption enumeration), `git_mounts_enabled` (the pure git-mount predicate), `refuse_outside_gitdir`/`absorb_submodules`/`prepare_git_host` (host-side git preparation: refusal when the gitdir lies outside `<project>` and `git submodule absorbgitdirs`), and the `fetch` action: `plan_fetch` assembles the no-network gitdir-bundle `podman run` (mounting the container's `<slug>.<container>.gitdir` volume read-only with `GIT_DIR=/gitdir` and `git bundle create --all`) followed by the host `git fetch <bundle> +refs/heads/*:refs/remotes/<container>/*`, executed by `execute_fetch_plan` from `run_fetch` (which handles `--all` across onbox/netbox/offbox and skips containers with no gitdir volume).
- `lib/naming.sh` - adds `gitdir_volume <project> <container>` returning `<project-slug>.<container>.gitdir`.
- `lib/options.sh` - parses the `fetch` subcommand verb (a bare positional `fetch`, distinct from `-c fetch`) and the repeatable `--all` flag (`ONBOX_ALL`, default `no`).
- `lib/containers.sh` - `plan_onbox`/`plan_netbox`/`plan_offbox` append the git mounts (`<project>/.git:/host/git:ro` and `<slug>.<container>.gitdir:/working/<base>/.git`) when `git_mounts_enabled`; the new `plan_gitdir_volume` step creates the gitdir volume (owned by the host user via `podman volume create`, idempotently skipping existing volumes) before every container create, including the recontain/rebuild plans and the netbox/offbox executors.
- `image/entrypoint.sh` - when the gitdir volume is present (i.e. `/host/git` exists), after applying dotfiles: `git init` the empty volume, wire the `host` remote at `/host/git/`, set the working tree (`core.worktree`), and perform an initial `git fetch host` + `git reset --mixed` (after pointing `HEAD` at the host's branch) so the working tree is connected to the host history without copying configs or hooks; subsequent starts only refresh the remote URL. Submodule git operations are blocked naturally because the container's gitdir volume is fresh and lacks `.git/modules/`.
- `talkbox.sh` - routes the `fetch` subcommand to `run_fetch` for all three containers and calls `prepare_git_host` (refusal + absorption) before the run/recontain/rebuild verbs.
- `MAP.gen.md` - records `lib/git.sh` and updated descriptions for `talkbox.sh`, `lib/naming.sh`, `lib/options.sh`, `lib/containers.sh` and `image/entrypoint.sh`.

## Verification

- The shared base image `talkbox/base:latest` was rebuilt so the e2e suite exercises the updated `entrypoint.sh`.
- `make test-unit` - exit `0`; 139/139 tests passed.
- `make test-e2e` - exit `0`; 42/42 tests passed.
- `make lint` - exit `0`; ShellCheck clean on all modified scripts (and on the repo's test scripts).
- `make format` - `shfmt` clean on all modified scripts and the repo's test scripts.
