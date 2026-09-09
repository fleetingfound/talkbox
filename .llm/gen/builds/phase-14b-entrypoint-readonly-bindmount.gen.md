# Phase 14b: Read-only bind-mount the entrypoint from the host

Status: `SUCCESS`

This build implements [phase-14b-entrypoint-readonly-bindmount.gen.md](../plans/phase-14b-entrypoint-readonly-bindmount.gen.md): each of the three persistent planners in `lib/containers.sh` (`plan_onbox`, `plan_netbox`, `plan_offbox`) now appends a read-only bind mount of the host file `$TALKBOX_ROOT/image/entrypoint.sh` at `/usr/local/bin/entrypoint.sh:ro`, grouped with the other `TALKBOX_ROOT`-sourced `:ro` mounts (the `merge.sh` and dotfiles mounts). The red tests added in `test/unit/containers.bats`, `test/unit/netbox-offbox.bats`, `test/e2e/onbox.bats` and `test/e2e/netbox-offbox.bats` were not edited. No verdict document was provided, no dispute was required, and no new issues were found.

## Overview

- `lib/containers.sh` - added the `-v "$TALKBOX_ROOT/image/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro"` entry to `plan_onbox`, `plan_netbox` and `plan_offbox` (unconditional, immediately after the git-mounts block and before the dotfiles mounts), so the host entrypoint shadows the image-layer `COPY` at runtime in all three persistent container types and is re-applied on every recontain/rebuild create.
- `image/Containerfile` - unchanged: the `COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh` is retained as the defence-in-depth fallback (bind-mount content is excluded from `podman commit`, so committed root images always carry the trusted image-layer entrypoint).
- `MAP.gen.md` - updated the `lib/containers.sh` description to mention the read-only entrypoint bind mount.

## Verification

- `make lint` - clean.
- `make format` - no formatting changes.
- `make test-unit` - exit `0`; 256/256 tests passed, including the nine new planner tests (onbox/netbox/offbox plan, onbox recontain/rebuild, netbox/offbox recontain/rebuild) asserting the `$TALKBOX_ROOT/image/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro` entry.
- `make test-e2e` - exit `0`; 75/75 tests passed with 0 skipped, including the new onbox tamper-resistance test (plain write and `sudo tee` both fail with `Read-only file system`, file content is the trusted entrypoint) and the netbox `--recontain` re-application test.
