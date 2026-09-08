# Phase 12d: IPv6 deny/allow via nft set difference (accept allow-set, then drop deny-set)

#flow/redgreen #model/default

## aspect of the specification

Implements the SPEC.md §"network" guarantee that, for `onbox` and `netbox`, access is always allowed to loopback addresses (`127.0.0.0/8`, `::1`) and `169.254.1.1` even when matched by `defaults/deny.ip`, and that `defaults/allow.ip` / `--allow-ip` entries override the deny list. Resolves the issue that IPv6 deny CIDRs do not have allowed entries (including `::1`) carved out of them.

Per the selected choice in [IPv6 deny/allow CIDR range carving approach](../choices/ipv6-deny-allow-carving-approach.gen.md), the Bash-side CIDR carving is eliminated entirely; the set difference is moved into the nftables ruleset, which performs CIDR matching natively for both IPv4 and IPv6.

Nothing in this phase is deferred — it fully resolves the IPv6 spec violation and simplifies the IPv4 path alongside it.

## external-facing functionality

- A broad IPv6 deny CIDR (e.g. `--deny-ip ::/0`) now correctly leaves `::1` (and any user-supplied IPv6 allow entry) reachable, because nft matches the allow set before the deny rule.
- IPv4 deny/allow behaviour is unchanged from the user's perspective (deny minus allow still enforced); only the internal mechanism changes.
- `offbox` is unaffected (no deny set, no nft rules installed).

## files to be created

None.

## files to be modified

- [lib/network.sh](../../../lib/network.sh) — the primary change site:
  - Remove the IPv4 carving helpers (`ipv4_int`, `ipv4_str`, `ipv4_prefix`, `ipv4_range`, `range_cidrs`) and `deny_allow_subtract` entirely.
  - Rework `deny_allow_args` to produce **two** output arrays instead of one: the deduplicated raw deny set and the deduplicated allow set (the latter including the always-allowed entries `127.0.0.0/8`, `169.254.1.1/32`, `::1`). No carving is performed.
  - Rework `nft_deny_family_ruleset` and `nft_deny_ruleset` so that, for each address family that has deny entries, the emitted ruleset defines two interval sets — an allow set and a deny set — and two rules in the output chain: an `accept` rule matching the allow set (placed first) followed by a `drop` rule matching the deny set. Families with deny entries but no allow entries emit only the deny set and drop rule. Families with no deny entries emit nothing (the chain's `policy accept` already permits traffic).
  - Update `plan_nft_deny` and `install_nft_deny` to carry both the deny and allow sets through to the ruleset emitter. `install_nft_deny` remains a no-op (and emits no `podman` invocation) when the deny set is empty; the allow set alone never triggers rule installation.
- [lib/containers.sh](../../../lib/containers.sh) — the `run_onbox`, `run_netbox`, `run_recontain`, `run_rebuild`, `run_netbox_recontain`, `run_netbox_rebuild` executors (the ones that call `install_nft_deny`): accept an additional allow-set nameref parameter and pass both deny and allow sets to `install_nft_deny`. The `run_offbox*` executors and any executor that does not install deny rules are unchanged in behaviour (they receive an empty allow set for threading symmetry, or are left as-is).
- [talkbox.sh](../../../talkbox.sh) — declare an allow-set array alongside the existing deny-set array in `onbox_action` and `sandbox_action`; populate it via the reworked `deny_allow_args`; thread both arrays through to every `run_*` executor call site. For `offbox`, both arrays remain empty (no `deny_allow_args` call).

## relevant files to read during implementation

- [lib/network.sh](../../../lib/network.sh) — current carving implementation and nft ruleset emitter.
- [lib/containers.sh](../../../lib/containers.sh) — executor signatures and `install_nft_deny` call sites.
- [talkbox.sh](../../../talkbox.sh) — deny/allow array threading into executors.
- [test/unit/network.bats](../../../test/unit/network.bats) — existing unit tests asserting the carved deny set and the single-set nft ruleset (to be rewritten).
- [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats) — existing e2e deny/allow enforcement tests (behavioural, should continue to pass).
- [.llm/gen/choices/ip-deny-allow-enforcement.gen.md](../choices/ip-deny-allow-enforcement.gen.md) — the original enforcement-mechanism choice (now superseded for the set-difference aspect by the IPv6 carving choice).
- [.llm/gen/choices/ipv6-deny-allow-carving-approach.gen.md](../choices/ipv6-deny-allow-carving-approach.gen.md) — the selected approach (Option D).

## key internal interfaces

- `deny_allow_args` — new two-array output interface (deny set + allow set, including always-allowed entries). The caller in `talkbox.sh` declares both arrays and passes their names.
- `nft_deny_ruleset` — accepts both deny and allow entries; emits per-family `accept`-then-`drop` rules using two interval sets. The ruleset text remains piped to `nft -f -` via the existing `podman unshare nsenter` command.
- `install_nft_deny` / `plan_nft_deny` — carry both sets; no-op when the deny set is empty.
- The `run_*` executor parameter lists gain an allow-set nameref; the plan functions are not touched by this phase (their dead `_deny` parameter is addressed by [Phase 13a](phase-13a-remove-dead-deny-nameref.gen.md)).

## tests

Requires tests to be implemented.

- **Unit tests** (in `test/unit/network.bats`):
  - Rewrite the `deny_allow_args` carving tests to assert the new two-array output: deny entries are returned raw (deduplicated, in order), allow entries are returned raw (deduplicated, including the always-allowed entries), and no carving occurs.
  - Rewrite the `nft_deny_ruleset` tests to assert the new two-set accept-then-drop ruleset per family, including: deny-only family (no allow set emitted), mixed deny+allow family (accept rule before drop rule), and a family present only in allow (emits nothing).
  - Add unit tests asserting that a broad IPv6 deny CIDR with an IPv6 allow entry (and with `::1` always-allowed) produces an nft ruleset where the allow set precedes the deny set for the `ip6` family — capturing the resolution of the reported issue at the ruleset level.
  - Update the `install_nft_deny` shim tests to thread both deny and allow sets and assert the no-op behaviour for an empty deny set.
- **End-to-end tests** (in `test/e2e/deny-allow.bats`):
  - The existing IPv4 deny/allow e2e tests should continue to pass unchanged (they assert external reachability, not implementation details).
  - Add an e2e test (gated on `nft` availability and IPv6 host connectivity, skipping gracefully otherwise) that denies a broad IPv6 CIDR (e.g. `::/0`) and asserts that `::1` remains reachable inside the container (e.g. via a loopback IPv6 `curl`), demonstrating the spec compliance end-to-end.
