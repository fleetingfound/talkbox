# Phase 14c: Install nft ruleset before entrypoint setup runs

Status: `SUCCESS`

This build implements [phase-14c-nft-before-entrypoint-setup.gen.md](../plans/phase-14c-nft-before-entrypoint-setup.gen.md): the persistent-container startup sequence is refactored so the setup body runs as `podman exec "$ctr" setup.sh` **after** `install_nft_deny_or_die` (onbox/netbox) or after `podman start` (offbox) instead of as the image `ENTRYPOINT` at `podman start`; `image/entrypoint.sh` is deleted and its body extracted into the new `image/setup.sh`, the tmpfs `/run/talkbox` sentinel and `wait_for_entrypoint` poll are removed, and the stopped-container `container_sync_cmd` path runs `setup.sh` explicitly before the sync script. No verdict document was provided, no dispute was required, and no new issues were found. Per the plan's issue-resolution section, [issue: agent-modified entrypoint runs before nft deny enforcement](../issues/agent-modified-entrypoint-pre-nft.gen.md) is marked complete in [.llm/gen/issues/INDEX.gen.md](../issues/INDEX.gen.md).

## Overview

- `image/setup.sh` (new, mode `0755`) - the setup body extracted from `image/entrypoint.sh`: global-then-project dotfiles copy into `/home/dev/`, the git-identity global-config writes from `TALKBOX_GIT_USER_NAME`/`TALKBOX_GIT_USER_EMAIL`, and the gitdir-init block (`git init` guarded by `rev-parse`, `remote add`/`set-url host /host/git/`, `git fetch host`, `git reset --mixed`); exits 0 on completion with no `exec` tail and no sentinel write.
- `image/entrypoint.sh` - deleted; the image no longer references it.
- `image/Containerfile` - `COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh` replaced by `COPY --chmod=755 setup.sh /usr/local/bin/setup.sh`; the `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]` directive removed so the planner-supplied `sleep infinity` is PID 1 directly.
- `lib/containers.sh` - the three persistent planners drop `--tmpfs /run/talkbox` and replace the read-only entrypoint bind mount with `-v "$TALKBOX_ROOT/image/setup.sh:/usr/local/bin/setup.sh:ro"`; `wait_for_entrypoint` is removed; the new `run_setup_in_container` helper runs `podman exec "$ctr" setup.sh` and, on failure, stops the container (with `STOP_GRACE_SECONDS`) and raises a `talkbox:` error (mirroring `install_nft_deny_or_die`); `run_onbox`/`run_netbox` reorder to start → nft → setup → user command, `run_offbox` to start → setup → user command, and the netbox/offbox recontain/rebuild executors insert setup between nft/start and the final `podman stop`; the stopped-container `container_sync_cmd` one-shot path now runs `bash -c 'setup.sh && exec bash -c "$0" _ "$@"' <script> <branches...>` on the no-longer-entrypoint image; `plan_volume_populate` is unchanged (a `cp` operation needs no setup).
- `MAP.gen.md` - the `lib/containers.sh` description now covers the setup.sh bind mount and post-nft synchronous setup; the deleted `image/entrypoint.sh` entry is replaced by an `image/setup.sh` entry.

## Verification

- `make test-unit` - exit `0`; 251/251 tests passed, including the reworked tmpfs-absence assertions, the executor-ordering shim tests (nft before `setup.sh` before the user command; setup failure stops the container with a `talkbox:` error) and the `container_sync_cmd` setup-before-script assertion.
- `make test-e2e` - exit `0`; 76/76 tests passed with 0 skipped, including the deny-allow e2e proving a deny-listed connection attempted during setup is blocked, the `setup.sh`-presence tests in onbox/netbox flows, and the git-identity setup-order regression test.
- ShellCheck and `shfmt` are clean on the modified shell files.
