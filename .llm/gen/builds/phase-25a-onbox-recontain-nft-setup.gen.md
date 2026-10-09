# Phase 25a: onbox `--recontain`/`--rebuild` install the nft deny rules and run `setup.sh`

*Date: 2026-10-09*

Status: **SUCCESS**

## overview

Implemented the plan in [phase-25a-onbox-recontain-nft-setup.gen.md](../plans/phase-25a-onbox-recontain-nft-setup.gen.md): `run_recreate` in [lib/containers.sh](../../../lib/containers.sh) now uses the `run_container`-shaped start-time tail — a single `!= offbox` guard around the nft install, followed by an unconditional `run_setup_in_container`, then the best-effort stop — replacing the nested `!= onbox` / `!= offbox` guards that skipped both steps for `onbox` on recontain/rebuild.

## implemented changes

- [lib/containers.sh](../../../lib/containers.sh) — `run_recreate`'s post-plan tail: `podman start` (from the plan), then `install_nft_deny_or_die` unless the container is `offbox`, then `run_setup_in_container`, then `stop_container`. No signature changed; the nested per-container asymmetry was deleted and no new interface was introduced.
- [MAP.gen.md](../../../MAP.gen.md) — updated the `lib/containers.sh` entry's description of the recreate executor's start-time tail.

The failing tests from the red phase (commit `e787730`) pin the new ordering (start < nft < `setup.sh` < stop) in [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats) and [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats); they were not modified.

## verification

- `make test-unit`: 315/315 pass
- `make test-e2e`: 78/78 pass
- `make lint` and `make format`: green

With an empty effective deny set (the e2e default) the nft step remains a no-op; `onbox --recontain`/`--rebuild` can now fail hard (container stopped, `talkbox:` error) when a non-empty deny set cannot be enforced, matching the create-path contract. `netbox`, `offbox` and all create-path behaviour are unchanged.

## resolution

This resolves [the issue](../issues/onbox-recontain-skips-nft-and-setup.gen.md), which is marked complete in [INDEX.gen.md](../issues/INDEX.gen.md), and unblocks Phase 25b (container consolidation). No disputes; no new issues.
