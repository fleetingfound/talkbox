# Phase 12c: IP deny/allow enforcement via nftables in the container netns

Status: `SUCCESS`

This build implements [phase-12c-ip-deny-allow-enforcement.gen.md](../plans/phase-12c-ip-deny-allow-enforcement.gen.md): the effective deny set computed in Phase 12b is now enforced for the `onbox` and `netbox` containers by installing an nftables interval-set ruleset in the container's network namespace via `podman unshare nsenter -t <PID> -n nft -f -` after `podman start`, with a `talkbox:` warning and continued startup (deny list unenforced) when the capability is unavailable, and no nft invocation at all for empty deny sets or any `offbox` path. No verdict, dispute or issue documents are linked.

## Overview

- `lib/network.sh` - added the enforcement interface: `nft_deny_ruleset <entry...>` prints a per-family (`ip`/`ip6`) interval-set ruleset (table `talkbox_deny`, set `blocked`, output hook with `policy accept`, `ip daddr @blocked drop` / `ip6 daddr @blocked drop`); `plan_nft_deny <out> <pid> <entry...>` appends the invocation tokens `podman unshare nsenter -t <pid> -n nft -f -` (nothing for an empty set); `install_nft_deny <container> <entry...>` is the best-effort installer — a no-op for an empty set, otherwise it resolves the container's init PID via `podman inspect -f '{{.State.Pid}}'`, pipes the ruleset into the planned command, and on any failure prints a `talkbox:` warning to stderr and returns success.
- `lib/containers.sh` - the `run_onbox` and `run_netbox` executors call `install_nft_deny "$ctr" "${_deny[@]}"` after `podman start` / `wait_for_entrypoint` and before `podman exec`; the `run_netbox_recontain` and `run_netbox_rebuild` executors call it after `execute_plan` (which starts the container). `run_offbox` and the offbox recontain/rebuild executors do not call it; an empty effective deny set is a no-op.
- `MAP.gen.md` - the `lib/network.sh` and `lib/containers.sh` entries updated to describe the enforcement step (replacing the "enforcement is deferred to Phase 12c" note).

## Verification

- `make lint` - clean.
- `make format` - no formatting changes.
- `make test-unit` - exit `0`; 243/243 tests passed (8 new `nft_deny_ruleset` / `plan_nft_deny` / `install_nft_deny` cases in `network.bats`).
- `make test-e2e` - exit `0`; 72/72 tests passed (4 `deny-allow.bats` cases: onbox/netbox `--deny-ip` blocking with a non-denied target still reachable, the shim-observed nft invocation for onbox with none for the allow-emptied set and offbox, and `--allow-ip` overriding `--deny-ip`).
