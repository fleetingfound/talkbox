# Phase 20d: shared no-network run prefix and git-mount plan tokens

Pinning-test pass for [phase-20d-no-net-run-and-git-mount-helpers](../plans/phase-20d-no-net-run-and-git-mount-helpers.gen.md), which centralises the repeated podman argument groups — the no-network temporary-container prefix (`podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000`) and the shared git-mount tokens (read-only host git dir, gitdir volume, read-only `merge.sh`) — into two helpers so they cannot drift between `lib/git.sh` and `lib/containers.sh`, with every emitted podman command line required to stay byte-identical. These tests pin the current exact token sequences so the refactor can proceed safely; no core files were modified.

## New tests

### test/unit/git.bats

1. `gitdir_bundle_cmd opens with the exact no-network run prefix before the gitdir and bundle mounts` — pins the bundle command's first eleven tokens exactly: `podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000` followed immediately by `-v <project-slug>.onbox.gitdir:/gitdir:ro`, `-v <bundle-dir>:/host/bundle` and `-e GIT_DIR=/gitdir`.

### test/unit/git-transport.bats

2. `container_sync_cmd no-network run opens with the exact prefix, --workdir directly after and the git mounts in order` — for the stopped-container branch, pins tokens 0–4 as the exact no-network prefix, `--workdir=/working/<base>` at token 5, and the complete ordered sequence of `-v` specs: gitdir volume at `/working/<base>/.git`, worktree volume at `/working/<base>`, host git dir read-only at `/host/git`, and `merge.sh` read-only at `/talkbox/lib/merge.sh`.

### test/unit/netbox-offbox.bats

3. `volume-population planner opens the run with the exact no-network prefix tokens` — pins tokens 0–4 of `plan_volume_populate` as the exact prefix for both the `host` (source mounted `:ro` at token 6) and `volume` (source mounted read-write at token 6) source kinds, with nothing intervening between prefix and first mount.
4. `netbox and offbox populate plans open every podman run with the exact no-network prefix` — across the four `podman run` commands of a combined `plan_netbox_populate` + `plan_offbox_populate` plan, pins that each opens with `run --rm --network=none --userns=keep-id:uid=1000,gid=1000`.
5. `run_netbox emits the three git mounts as consecutive tokens in the shared order` — pins that the `podman create` line contains the shared git-mount triple as one consecutive `-v <host git>:/host/git:ro -v <slug>.netbox.gitdir:/working/<base>/.git -v <root>/lib/merge.sh:/talkbox/lib/merge.sh:ro` sequence.

## Edited tests

None. All existing command-array tests named by the plan — `plan_fetch`/`gitdir_bundle_cmd` in `test/unit/git.bats` and `test/unit/git-transport.bats`, `plan_volume_populate`/`plan_netbox_populate`/`plan_offbox_populate` in `test/unit/netbox-offbox.bats`, and the `container_sync_cmd` no-network run test in `test/unit/git-transport.bats` — pass unchanged, as the plan requires.

## Removed tests

None.
