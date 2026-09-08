# Phase 12d: IPv6 deny/allow via nft set difference

Status: `SUCCESS`

This build implements [phase-12d-ipv6-deny-allow-nft-set-difference.gen.md](../plans/phase-12d-ipv6-deny-allow-nft-set-difference.gen.md): the Bash-side CIDR carving is removed entirely and the deny-minus-allow set difference moves into the nftables ruleset, which emits, per address family with deny entries, an `allowed` interval set plus an `accept` rule placed before the `blocked` set's `drop` rule — so loopback (`127.0.0.0/8`, `::1`) and `169.254.1.1` (plus user `--allow-ip`/`defaults/allow.ip` entries) remain reachable even under a broad IPv6 deny CIDR such as `::/0`. The always-allowed carve-out issue [ipv6-deny-allow-no-cidr-carving.gen.md](../issues/ipv6-deny-allow-no-cidr-carving.gen.md) is resolved (marked complete in the issues index); no verdict or dispute documents apply and no new issues were found.

## Overview

- `lib/network.sh` - removed the IPv4 carving helpers (`ipv4_int`, `ipv4_str`, `ipv4_prefix`, `ipv4_range`, `range_cidrs`) and `deny_allow_subtract` entirely. `deny_allow_args <deny-out> <allow-out> <deny-file> <allow-file> <deny-cli> <allow-cli>` now returns the deduplicated raw deny set and the deduplicated allow set (user file/CLI entries followed by the always-allowed `127.0.0.0/8`, `169.254.1.1/32`, `::1`), without carving. `nft_deny_ruleset <deny-array> <allow-array>` emits a two-set accept-then-drop ruleset per family (`nft_deny_family_ruleset` emits `allowed`/`blocked` interval sets via `nft_interval_set` plus `@allowed accept` before `@blocked drop`); families with deny entries but no allow entries emit only the blocked set and drop rule, and families without deny entries emit nothing. `plan_nft_deny <out> <pid> <deny-array> <allow-array>` and `install_nft_deny <ctr> <deny-array> <allow-array>` carry both sets and remain no-ops (no `podman` invocation) when the deny set is empty.
- `lib/containers.sh` - the `run_onbox`, `run_netbox`, `run_netbox_recontain` and `run_netbox_rebuild` executors (the `install_nft_deny` call sites) now take an additional allow-set nameref parameter and call `install_nft_deny "$ctr" <deny-name> <allow-name>`; the remaining container `run_*` executors (including the offbox paths) also accept the allow-set nameref for call-site symmetry while remaining behaviourally unchanged.
- `talkbox.sh` - `onbox_action` and `sandbox_action` declare an `allow_ips` array next to `deny_ips`, populate both via the reworked `deny_allow_args` (`offbox` skips the call, leaving both arrays empty) and thread both arrays through every container `run_*` executor call site.
- `MAP.gen.md` - the `talkbox.sh`, `lib/network.sh` and `lib/containers.sh` entries updated to describe the raw two-set interface and the nft accept-then-drop enforcement.
- `.llm/gen/issues/INDEX.gen.md` - the IPv6 carving issue marked resolved by this phase.

## Verification

- `make lint` - clean.
- `make format` - no formatting changes.
- `make test-unit` - exit `0`; 242/242 tests passed (network.bats deny/allow tests rewritten to the two-array contract, the two-set ruleset and the empty-deny no-op).
- `make test-e2e` - exit `0`; 73/73 tests passed with 0 skipped, including the new `onbox --deny-ip ::/0` test asserting `::1` stays reachable inside the container and the inverted shim assertion that an allow entry alongside a deny entry still triggers the nft installer.
