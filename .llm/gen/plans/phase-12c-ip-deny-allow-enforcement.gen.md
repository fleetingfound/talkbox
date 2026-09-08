# Phase 12c: IP deny/allow enforcement via nftables in the container netns

#flow/redgreen #model/default

## Aspects of SPEC.md implemented

Implements the enforcement aspect of the IP deny/allow feature from the `## network` section of `SPEC.md`:

- For the `onbox` and `netbox` containers, IP addresses and CIDR ranges in the effective deny set (computed in [Phase 12b](phase-12b-ip-deny-allow-parsing.gen.md)) are blocked.
- Loopback addresses and `169.254.1.1` are always reachable (already guaranteed by the effective-set computation).
- `allow.ip` entries override `deny.ip` (already guaranteed by the effective-set computation).
- These options do not affect `offbox`.

This realises the [IP deny/allow enforcement mechanism](../choices/ip-deny-allow-enforcement.gen.md) choice: nftables rules installed in the container's network namespace, post-start, via `nsenter` (acquiring `CAP_NET_ADMIN` through `podman unshare`).

### Aspects deferred

None for this feature. (Out-of-scope: per-port or per-protocol filtering — the deny set applies to all outbound traffic to the matched destinations.)

## External-facing functionality

- After an `onbox` or `netbox` container starts, outbound traffic from the container to any address/CIDR in the effective deny set is dropped.
- Outbound traffic to all other addresses (including loopback and `169.254.1.1`) is unaffected.
- `offbox` containers are unaffected by `deny.ip` / `allow.ip`.
- If the nftables rule installation cannot acquire the required capability (e.g. `nft` or `nsenter` unavailable, or `podman unshare` cannot grant `CAP_NET_ADMIN`), talkbox prints a `talkbox:` warning to stderr and continues starting the container, with the deny list left unenforced, rather than aborting.

## Files to be created

None. All changes are to existing files.

## Files to be read during implementation

- [lib/network.sh](lib/network.sh) — the effective-deny-set function from Phase 12b.
- [lib/containers.sh](lib/containers.sh) — `run_onbox`, `run_netbox`, `run_offbox`, the netbox/offbox recontain and rebuild executors, and the `wait_for_entrypoint` helper (rules must be installed after the netns is up).
- [talkbox.sh](talkbox.sh) — action functions threading the effective deny set.
- [.llm/ref/passt.docs/passt.1](.llm/ref/passt.docs/passt.1) — confirm pasta netns ownership model.
- [.llm/ref/linux.man/capabilities.7.txt](.llm/ref/linux.man/capabilities.7.txt) — `CAP_NET_ADMIN` semantics.

## Key internal interfaces to be modified

- `lib/network.sh`: add a function that, given a container name and the effective deny-set array, (a) obtains the container's init PID via `podman inspect`, (b) builds an `nft` ruleset that creates an interval set of the denied destinations and a rule dropping outbound traffic to that set, and (c) applies it via `podman unshare nsenter -t <PID> -n nft -f -`. The function is best-effort: on failure it emits a `talkbox:` warning and returns success.
- `lib/containers.sh`: the `run_onbox` and `run_netbox` executors call the nft-installation function after `podman start` / `wait_for_entrypoint` and before `podman exec`, passing the threaded effective deny set. The netbox recontain/rebuild executors (which `podman start` the container) do the same. `run_offbox` and the offbox recontain/rebuild executors do not call it.
- The deny set is only applied when it is non-empty; an empty effective set is a no-op (no nft invocation), keeping the common case cheap.

## Tests

Requires tests, including:

- unit tests:
  - the nft-installation planner builds the expected `nsenter` / `nft` invocation tokens from a sample deny set (without running podman), including the interval-set construction and the `podman unshare` wrapper.
  - an empty deny set produces no invocation.
- end-to-end tests:
  - an `onbox` (or `netbox`) container started with `--deny-ip <host-side-test-address>` cannot reach a server bound to that address, while a non-denied address remains reachable. The test uses the existing `host_http_server.py` pattern (or a second server) to provide reachable and unreachable targets, and runs the container via `-c --noninteractive` under `systemd-run`.
  - an `offbox` container ignores `--deny-ip` (the option is accepted but no filtering is applied beyond the existing offbox network restriction).
  - a deny entry overridden by an `--allow-ip` entry remains reachable.
  - The test suite must not depend on a GPU and must use a temporary git repository or non-git folder as the stand-in `<project>`.

## Verification

`make lint`, `make format`, `make test-unit`, `make test-e2e`.
