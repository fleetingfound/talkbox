# Phase 14b: Read-only bind-mount the entrypoint from the host

Test document for [Phase 14b: Read-only bind-mount the entrypoint from the host](.llm/gen/plans/phase-14b-entrypoint-readonly-bindmount.gen.md), which adds a `-v "$TALKBOX_ROOT/image/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro"` entry to the `plan_onbox`/`plan_netbox`/`plan_offbox` persistent-container planners (and thereby to the recontain/rebuild plans) so the in-container `COPY`-ed entrypoint is shadowed at runtime by a read-only bind mount of the trusted host file, closing the in-container tampering vector and the `podman commit` propagation vector of [agent-modified entrypoint runs before nft deny enforcement](.llm/gen/issues/agent-modified-entrypoint-pre-nft.gen.md) (the pre-nft ordering of the trusted entrypoint body remains open until [Phase 14c](.llm/gen/plans/phase-14c-nft-before-entrypoint-setup.gen.md)).

## New tests

### `test/unit/containers.bats` (3 tests)

Each follows the existing `array_contains` mount-assertion pattern (e.g. the dotfiles mount at L109) against `$TALKBOX_ROOT/image/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro`:

- `onbox plan bind-mounts the host entrypoint read-only` — `plan_onbox` emits the entrypoint `:ro` mount. **Observed red:** no entrypoint mount exists in the plan array today.
- `onbox recontain plan propagates the entrypoint read-only bind mount to podman create` — mirrors the tmpfs-propagation pattern (L356): `plan_recontain` emits the mount (asserted on the whole plan, whose `podman create` args come from `plan_onbox`). **Observed red.**
- `onbox rebuild plan propagates the entrypoint read-only bind mount to podman create` — mirrors `plan_rebuild` (L364). **Observed red.**

### `test/unit/netbox-offbox.bats` (6 tests)

Same assertion and propagation-mirroring approach as above:

- `netbox plan bind-mounts the host entrypoint read-only` — `plan_netbox` emits the mount. **Observed red.**
- `offbox plan bind-mounts the host entrypoint read-only` — `plan_offbox` emits the mount. **Observed red.**
- `netbox recontain plan propagates the entrypoint read-only bind mount to podman create` — mirrors the netbox tmpfs-propagation pattern (L491). **Observed red.**
- `offbox recontain plan propagates the entrypoint read-only bind mount to podman create` — mirrors L500. **Observed red.**
- `netbox rebuild plan propagates the entrypoint read-only bind mount to podman create` — mirrors L509. **Observed red.**
- `offbox rebuild plan propagates the entrypoint read-only bind mount to podman create` — mirrors L518. **Observed red.**

### `test/e2e/onbox.bats` (1 test)

- `onbox entrypoint is a read-only bind mount that resists tampering` — per the plan's e2e requirement: a direct write of `/usr/local/bin/entrypoint.sh` as `dev` must fail with a read-only-filesystem error (`EROFS`), the same overwrite via `sudo tee` must also fail, and the file's first line must remain the trusted entrypoint (`#!/usr/bin/env bash`). **Observed red:** today the image-layer file is root-owned and plain-writable via `sudo tee`, so the direct write fails with `Permission denied` (not `Read-only file system`) and the `sudo tee` attempt succeeds and overwrites the file.

### `test/e2e/netbox-offbox.bats` (1 test)

- `netbox --recontain re-applies the trusted entrypoint after a tampering attempt` — per the plan's e2e requirement: after the netbox container is created (committing onbox into the netbox root image), a `sudo tee` tampering attempt must be blocked, `netbox --recontain` must recreate the container, and the recreated container's entrypoint must still be the trusted file — validating both the `EROFS` claim and that the committed root image did not capture a tampered entrypoint while the planner re-applies the `:ro` bind mount on the recreated container. **Observed red:** today `sudo tee` succeeds inside the netbox container (`TAMPER-OK` instead of `TAMPER-BLOCKED`).

## Tests edited

- None. Existing tests were not modified; the new tests are appended alongside the analogous dotfiles/tmpfs mount tests.

## Tests removed

- None. No pre-existing test is inconsistent with the plan: no existing test asserts the absence of an entrypoint mount or an exact full argument list, and every pre-existing unit and e2e test continues to pass alongside the new failing tests (unit: 247 pass, 9 new fail; e2e: 73 pass, 2 new fail). The retained image-layer `COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh` in the Containerfile is unchanged per the plan.
