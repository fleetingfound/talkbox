# Issue: IPv6 deny/allow does not perform CIDR range carving

## summary

`deny_allow_subtract` in [lib/network.sh](../../../lib/network.sh) performs CIDR range subtraction (carving allowed ranges out of denied ranges) only for IPv4 entries. For IPv6 entries (any entry containing `:`), it falls back to exact string matching against allow entries. As a result, a broad IPv6 deny CIDR does not have allowed IPv6 addresses carved out of it.

## affected files

- [lib/network.sh](../../../lib/network.sh) — `deny_allow_subtract()` (the `if [[ "$deny" == *:* ]]` branch, lines ~89-97).

## spec violation

[SPEC.md](../../../SPEC.md) §"network" states:

> Access is always allowed to loopback addresses and `169.254.1.1` since it is used for DNS forwarding, even if those addresses are matched by `defaults/deny.ip`.

The always-allowed list appended in `deny_allow_args` includes `::1` (the IPv6 loopback). Because IPv6 subtraction is string-only, denying any IPv6 CIDR that *contains* `::1` but is not exactly `::1` or `::1/128` leaves `::1` in the deny set, so the generated nftables rule would drop egress to the container's own IPv6 loopback.

## reproduction

```bash
source lib/common.sh && source lib/network.sh
out=() deny_cli=() allow_cli=()
printf '::/0\n' >/tmp/deny.ip
: >/tmp/allow.ip
deny_allow_args out /tmp/deny.ip /tmp/allow.ip deny_cli allow_cli
printf '  [%s]\n' "${out[@]}"   # -> [::/0]   (::1 NOT carved out)
```

Contrast with the IPv4 path, where `0.0.0.0/0` correctly produces a deny set that excludes `127.0.0.0/8` and `169.254.1.1/32` (38 carved CIDR fragments).

## impact

Medium-low. The shipped `defaults/deny.ip` contains only IPv4 entries, so the default configuration is unaffected. The gap is triggered only when a user supplies a broad IPv6 deny CIDR (e.g. `--deny-ip ::/0` or `::/0` in `defaults/deny.ip`). In that case the container's IPv6 loopback would be blocked, which can break local services binding `::1`.

## suggested fix

Implement IPv6 range arithmetic analogous to the IPv4 path (`ipv6_int`/`ipv6_str`/`ipv6_range`/`range_cidrs` for 128-bit integers, which Bash cannot hold natively — would require splitting into two 64-bit words or delegating to a helper), or at minimum special-case the always-allowed `::1` against any IPv6 deny CIDR that contains it.
