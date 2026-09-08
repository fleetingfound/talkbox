# Phase 12b: IP deny/allow parsing, option threading and onbox/netbox pasta string

Status: `SUCCESS`

This build implements [phase-12b-ip-deny-allow-parsing.gen.md](../plans/phase-12b-ip-deny-allow-parsing.gen.md): `defaults/deny.ip` / `defaults/allow.ip` and repeatable `--deny-ip` / `--allow-ip` are parsed into an effective deny set (deny minus allow minus always-allowed loopback/`169.254.1.1`, with IPv4 CIDR-containment carving) that is threaded through the `onbox`/`netbox` executors and recontain/rebuild planners for enforcement in [Phase 12c](../plans/phase-12c-ip-deny-allow-enforcement.gen.md), and the `onbox`/`netbox` pasta network strings now include `--dns-forward,169.254.1.1,--map-guest-addr,none` (offbox unchanged). No verdict, dispute or issue documents are linked.

## Overview

- `lib/options.sh` - added the `TALKBOX_DENY_IP=()` / `TALKBOX_ALLOW_IP=()` arrays and the repeatable `--deny-ip` / `--allow-ip` option cases, each dying with `talkbox: <option> requires a value` and exit 2 when the final argument is missing, mirroring `--read` / `--write` / `--port`.
- `lib/network.sh` - added `deny_allow_args <out> <deny-file> <allow-file> <deny-cli> <allow-cli>` (CLI arrays by nameref): reads both files (blank/`#`-comment lines ignored, whitespace trimmed, matching `port_args`), unions the CLI arrays, deduplicates the deny entries, appends the always-allowed `127.0.0.0/8`, `169.254.1.1/32` and `::1`, and subtracts the allow entries from each deny entry via `deny_allow_subtract` (host entries match exactly; IPv4 CIDR allows carve the covered range out of a broader deny CIDR, re-emitting aligned CIDRs; IPv6 supports equality removal only). Pure bash — no podman.
- `lib/containers.sh` - `plan_onbox` and `plan_netbox` append `--dns-forward,169.254.1.1,--map-guest-addr,none` to the pasta network token (after any `-T,<port>` tokens); `plan_offbox` is unchanged. The `run_*` executors and the recontain/rebuild planners gain a deny-set nameref parameter (accepted but not yet consumed — enforcement is deferred); the recontain/rebuild planner parameters are optional so existing six- and nine-argument callers remain valid.
- `talkbox.sh` - `onbox_action` and the `netbox` branch of `sandbox_action` call `deny_allow_args` with `$TALKBOX_ROOT/defaults/deny.ip` / `defaults/allow.ip` and `TALKBOX_DENY_IP` / `TALKBOX_ALLOW_IP`, and thread the resulting array into `run_onbox` / `run_netbox` and the recontain/rebuild executors; `offbox` receives an empty array (the deny set is not computed for it).
- `MAP.gen.md` - the `talkbox.sh`, `lib/options.sh`, `lib/network.sh` and `lib/containers.sh` entries updated to describe the new deny/allow parsing and threading.

## Verification

- `make lint` - clean.
- `make format` - no formatting changes.
- `make test-unit` - exit `0`; 235/235 tests passed (19 new `deny_allow_args` cases in `network.bats` and 5 new `--deny-ip` / `--allow-ip` cases in `options.bats`, plus the updated pasta-string and planner-signature tests in `containers.bats` and `netbox-offbox.bats`).
- `make test-e2e` - exit `0`; 68/68 tests passed (no e2e tests in this phase, per the plan).
