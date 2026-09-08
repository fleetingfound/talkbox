# IPv6 deny/allow CIDR range carving approach

`deny_allow_subtract` in [lib/network.sh](../../../lib/network.sh) carves allowed ranges out of denied ranges for IPv4 entries using pure-Bash 32-bit integer arithmetic (`ipv4_int`/`ipv4_str`/`ipv4_prefix`/`ipv4_range`/`range_cidrs` and a family-agnostic subtraction loop). For IPv6 entries it falls back to exact string matching, so a broad IPv6 deny CIDR (e.g. `::/0`) does not have allowed entries (including the always-allowed `::1`) carved out of it. This violates the SPEC.md §"network" guarantee that loopback and `169.254.1.1` are always reachable.

The open design choice is how to perform IPv6 range subtraction given that Bash cannot hold a 128-bit integer natively.

## Option A: Pure Bash, four 32-bit words (Recommended)

Represent each 128-bit IPv6 value as a quadruple of 32-bit words (each comfortably within Bash's signed 64-bit range). Implement `ipv6_words` (parse a CIDR/address into four words), `ipv6_str` (format four words back to canonical text), `ipv6_range` (compute start/end word-quadruples for a CIDR), and `range_cidrs_v6` (split a word-quadruple range into aligned CIDR fragments). The existing subtraction loop in `deny_allow_subtract` is already family-agnostic (it operates on `(start, end)` integer pairs held in the `iv` array); generalize it to carry four-word values per endpoint, or factor the subtraction into a shared routine parameterised by word-compare/word-inc/word-dec helpers. The IPv4 path keeps its existing single-integer representation.

**Pros:** consistent with the established pure-Bash carving design and the project's "pure Bash, no extra runtime dependencies" convention; the IPv4 path is untouched; fully unit-testable by sourcing `lib/network.sh` alone; resolves the spec violation completely (user-supplied IPv6 allow CIDRs are also honoured as sub-range exceptions).
**Cons:** substantial new code (multi-word compare/increment/decrement/CIDR-split subroutines); careful testing required for alignment and boundary cases across 128 bits.

## Option B: Delegate IPv6 arithmetic to `python3`

Keep the IPv4 path in Bash; for IPv6 entries, shell out to `python3` (using the `ipaddress` module) to compute the carved deny set as a newline-delimited list of CIDRs. `python3` is already a test dependency but is not currently a runtime dependency of the core script.

**Pros:** trivially correct IPv6 arithmetic with minimal new Bash code; `ipaddress` handles all alignment and boundary cases.
**Cons:** introduces `python3` as a hard runtime dependency of the core script (SPEC.md states "All shell scripts should be implemented in Bash"); degrades gracefully only if python3 is absent (would need a fallback, reintroducing the bug); inconsistent that IPv4 is pure Bash but IPv6 shells out.

## Option C: Minimum special-case — carve only `::1` out of IPv6 deny CIDRs

Special-case the always-allowed `::1` against any IPv6 deny CIDR that contains it (using a targeted containment check), while leaving user-supplied IPv6 allow entries as exact string matches. This resolves the specific spec violation (IPv6 loopback always reachable) without implementing general IPv6 range arithmetic.

**Pros:** smallest possible change; addresses the reported spec violation directly; pure Bash.
**Cons:** does not honour user-supplied IPv6 allow CIDRs that are sub-ranges of an IPv6 deny CIDR (e.g. `--deny-ip ::/0 --allow-ip 2001:db8::/32` would not carve `2001:db8::/32` out); inconsistent with the IPv4 path's full carving; leaves a known correctness gap that a future user will likely hit.

## Selected

Option D — move the set difference into `nft`. Eliminate Bash-side carving for both families; emit an `accept` rule matching the allow set (including always-allowed entries) before a `drop` rule matching the raw deny set in the nft ruleset, relying on nft's native CIDR matching for both IPv4 and IPv6. Confirmed by user.

Eliminate Bash-side carving for *both* families. Emit two interval sets per family in the nft ruleset: an `accept` rule matching the allow set (including the always-allowed entries) placed before a `drop` rule matching the raw deny set. nft evaluates rules in order, so allowed destinations are accepted before the deny rule is reached, achieving the set difference natively. This removes `ipv4_int`/`ipv4_str`/`ipv4_prefix`/`ipv4_range`/`range_cidrs`/`deny_allow_subtract` entirely and changes `deny_allow_args` to return the deduplicated deny and allow sets separately.

**Pros:** simplest and most correct — nft performs CIDR matching natively for both IPv4 and IPv6, eliminating the entire class of bug; drastically reduces `lib/network.sh` code volume; no multi-word arithmetic.
**Cons:** contradicts the selected design in [IP deny/allow enforcement mechanism](ip-deny-allow-enforcement.gen.md) ("effective set computed in pure Bash, emitted as nft interval set"); larger refactor that touches the established unit and e2e tests for the deny/allow ruleset; changes the `install_nft_deny`/`run_*` interface (deny and allow arrays must both reach the executor); scope exceeds the reported issue.
