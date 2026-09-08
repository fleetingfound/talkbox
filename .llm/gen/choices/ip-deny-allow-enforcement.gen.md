# IP deny/allow enforcement mechanism

`SPEC.md` requires that, for the `onbox` and `netbox` containers, IP addresses and CIDR ranges listed in `defaults/deny.ip` (plus `--deny-ip` arguments) are blocked, with `defaults/allow.ip` (plus `--allow-ip`) overriding the deny list, and loopback addresses plus `169.254.1.1` always allowed. These options do not affect `offbox`.

`pasta` (the rootless networking backend used by podman) has **no native per-destination IP deny/allow filtering**. Its options only select the outbound interface, source address, gateway and port forwarding. The offbox "no internet" behaviour is achieved by forcing the outbound interface to `lo` (`-i,lo`), which is a coarse all-or-nothing switch, not a per-CIDR filter.

Therefore the deny/allow list must be enforced by a firewall ruleset installed in the container's network namespace. The open design choice is which firewall tool and application strategy to use.

## Option A: nftables rules in the container netns, applied post-start via `nsenter` (Recommended)

After `podman start` (and before `podman exec`), obtain the container's init PID via `podman inspect`, then enter its network namespace with `nsenter -t <PID> -n` and install an `nft` ruleset that drops outbound traffic whose destination matches the effective deny set (deny minus allow minus the always-allowed loopback/`169.254.1.1` entries). The ruleset lives in the netns and is destroyed automatically when the container (and its netns) is removed, so no explicit teardown is needed.

To gain `CAP_NET_ADMIN` in the rootless netns, the rule-installation step is run via `podman unshare nsenter ...` so the host user enters podman's user namespace as root before entering the target netns. If the capability is unavailable, talkbox warns and continues (deny list not enforced) rather than aborting the container start.

The effective deny set is computed in pure Bash (set subtraction of allow from deny, then removal of the always-allowed addresses) and emitted as an `nft` set with `flags interval` so CIDR ranges are matched correctly.

**Pros:** `nft` is the modern Linux firewall; interval sets map directly onto CIDR lists; rules are scoped to the ephemeral container netns so host firewall state is never touched; aligns with the existing planner/executor model (rules applied in `run_onbox`/`run_netbox` and the recontain/rebuild executors).
**Cons:** depends on `nft` and `nsenter` being present; rootless `CAP_NET_ADMIN` acquisition via `podman unshare` needs empirical validation on the target system; adds a post-start step to every onbox/netbox start.

## Option B: iptables/ip6tables rules in the container netns, applied post-start via `nsenter`

Same application strategy as Option A, but using the legacy `iptables`/`ip6tables` commands instead of `nft`. One rule per denied CIDR is appended to the `OUTPUT` chain (or a dedicated chain).

**Pros:** wider availability on older systems; familiar syntax.
**Cons:** legacy tooling (deprecated in favour of `nft`); one rule per entry is less compact than an interval set; separate IPv4/IPv6 invocations; does not match the modern stack the rest of the project assumes.

## Option C: host-side nftables targeting the pasta tap interface

Apply `nft` rules in the host's init network namespace, matching traffic on the tap device that pasta creates for the container.

**Pros:** no `nsenter`/userns acrobatics; rules visible from the host.
**Cons:** requires host `CAP_NET_ADMIN` (i.e. root), breaking the rootless model; identifying the per-container tap device name is fragile; host firewall state is mutated and must be explicitly cleaned up on container removal; high risk of leaving orphaned rules. Not recommended.

## Option D: pre-created netns managed by talkbox, attached via `--network=ns:`

Create the network namespace ourselves (via `unshare -r -n`), install `nft` rules there as root of the new userns, run `pasta` manually, and pass the netns to podman with `--network=ns:/proc/<PID>/ns/net`.

**Pros:** full control over the netns and its firewall; `CAP_NET_ADMIN` is held by construction.
**Cons:** large restructure of the networking setup that currently delegates entirely to podman's `--network=pasta:` integration; duplicates pasta lifecycle management; significant new failure surface. Out of proportion to the feature.

## Selected

Option A — nftables rules in the container netns, applied post-start via `nsenter` (using `podman unshare` to acquire `CAP_NET_ADMIN` in the rootless netns). Confirmed by user. If the capability is unavailable, talkbox warns and continues with the deny list unenforced rather than aborting the container start.
