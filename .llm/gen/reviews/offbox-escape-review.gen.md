# Offbox sandbox escape review — host and internet access

**Scope.** Determine whether the `offbox` container can gain access to **the
host** or **the internet** in a manner forbidden by [SPEC.md](SPEC.md). Per
SPEC, `offbox` "disables internet access" and "disables edits to the host", and
"is never given write access to the host system. Every mount it receives is
either a read-only bind-mount or a volume." The review combines static analysis
of the implementation ([talkbox.sh](talkbox.sh),
[lib/network.sh](lib/network.sh), [lib/containers.sh](lib/containers.sh),
[image/Containerfile](image/Containerfile)) with **active exploitation** of a
live `offbox` container created via `offbox -c`.

**Verdict.** No SPEC-forbidden access was found. From inside `offbox`:

- **The internet is unreachable** over every vector tested (IPv4/IPv6 direct
  connect, route injection, raw sockets, DNS forwarder, external DNS).
- **The host is unreachable** except through the **deliberate, port-scoped
  loopback channel** that SPEC explicitly sanctions ("all three containers
  require access to specific ports on the host … to access tools like local
  language models"). With the default empty `defaults/ports`, even that channel
  is closed.
- **No writable host path exists.** Every host-backed mount is read-only; all
  writable mounts are podman volumes (copies).

The isolation is nonetheless **single-layered** (see
[Hardening observations](#hardening-observations)): it rests entirely on the
guest routing table containing no non-loopback route, which in turn rests on
`CAP_NET_ADMIN` being dropped. There is no `nftables` egress backstop for
`offbox`. Recommendations are recorded at the end.

## Environment observed

Live `offbox` container for a throwaway git project, created with the repo's
`offbox` command. Host facts (for reference): public IP `65.21.242.153`,
default gateway `172.31.1.1` on `eth0`, SSH on `:22`.

The actual `pasta` invocation podman launched for `offbox` (captured from the
host process table, matched by the container's netns):

```
/usr/bin/pasta --config-net -i lo -I talkbox0 --dns-forward 169.254.1.1 \
  -t none -u none -T none -U none --no-map-gw --quiet \
  --netns <ns> --map-guest-addr 169.254.1.2
```

This confirms the SPEC-mandated offbox options `-i lo` and `-I talkbox0` were
applied (the in-namespace interface is named `talkbox0`). podman additionally
injects its own defaults: `--dns-forward 169.254.1.1`, `-t/-u/-T/-U none` (no
port forwarding), `--no-map-gw`, and `--map-guest-addr 169.254.1.2`. Each of
these injected options was tested below and none opens a path off the box,
because `-i lo` strips every non-loopback route.

### Network configuration inside the container

- Interfaces: `lo` and `talkbox0` only.
- IPv4 routing table (`/proc/net/route`): a **single** route,
  `127.0.0.0/8 dev talkbox0`. **No default route.** No route to any host IP,
  LAN, or public address.
- IPv6: only `fe80::/64` (link-local) on `talkbox0` and `::1` on `lo`. No
  default route, no global address.
- `/etc/resolv.conf`: `nameserver 185.12.64.2` — the **host's real upstream
  resolver** (see [Hardening observations](#hardening-observations)).

Because the container's only route is loopback via the pasta tap, the guest
kernel returns `ENETUNREACH` for every non-loopback destination before a packet
ever reaches pasta. This — not an `nftables` rule — is what blocks egress.

### Capabilities

Measured `CapBnd = 0x800405fb`; `podman inspect .BoundingCaps` =
`CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, NET_BIND_SERVICE, SETFCAP, SETGID,
SETPCAP, SETUID, SYS_CHROOT`. Critically **absent**: `NET_ADMIN` (bit 12),
`NET_RAW` (bit 13), `SYS_ADMIN`, `SYS_PTRACE`. As `dev`, `CapEff = 0`.

`sudo NOPASSWD:ALL` is present in the image and grants full root **within the
container's user namespace**, but the bounding set is unchanged after `sudo`
(`0x800405fb`) — a dropped capability cannot be re-acquired.

## Attack vectors tested

### Internet — all blocked

| Vector | Method | Result |
|---|---|---|
| Direct TCP, IPv4 external | `connect(1.1.1.1:443)`, `8.8.8.8:53` | `ENETUNREACH` |
| Direct TCP, IPv6 external | `connect([2606:4700:4700::1111]:443)` | `ENETUNREACH` |
| External DNS in resolv.conf | TCP+UDP to `185.12.64.2:53` | `ENETUNREACH` |
| DNS forwarder | `connect(169.254.1.1:53)` | `ENETUNREACH` |
| **Route injection** | root `sudo`, netlink `RTM_NEWROUTE` add default route via `talkbox0` | **`EPERM`** (no `NET_ADMIN`) |
| Raw sockets | root `sudo`, `socket(AF_INET, SOCK_RAW, ICMP)` | **`EPERM`** (no `NET_RAW`) |

The netlink test is the decisive one: since the routing table is the *only*
barrier to the internet, the ability to add a route would defeat it entirely.
It is rejected with `EPERM` even as container-root, because `CAP_NET_ADMIN` is
outside the bounding set and cannot be regained.

### Host — blocked except the sanctioned port channel

| Vector | Method | Result |
|---|---|---|
| Host public IP | `connect(65.21.242.153:22)` | `ENETUNREACH` |
| Host gateway | `connect(172.31.1.1:22)` | `ENETUNREACH` |
| Host loopback, **no** `--port` | `connect(127.0.0.1:54321)` to a live host marker; `127.0.0.1:22` (host SSH) | **Connection refused** — reaches pasta, but pasta forwards nothing; the marker did **not** respond |
| podman `--map-guest-addr` target | `connect(169.254.1.2:{22,80,443,54321})` (= host global addr) | `ENETUNREACH` (no route to `169.254/16`) |
| Gateway→host mapping | (default `--map-host-loopback`) | Off: `--no-map-gw` + no gateway/default route |
| **Host loopback, `--port 54321`** | recreate with `offbox --port 54321`; `connect(127.0.0.1:54321)` | **OPEN** — returned the host marker's HTTP response |
| Host loopback, unforwarded port under `--port 54321` | `connect(127.0.0.1:22)` | Connection refused |
| Host `.git` write | `echo x > /host/git/PWNED` | **`Read-only file system`**; no marker file appeared on host |
| Worktree write reaching host | write to `/working/<proj>/…` | Succeeds into the **volume**; host tree unaffected |

The `--port` result is the whole security boundary in one line: `offbox` is
**not air-gapped** — `pasta -T,<port>` forwards `127.0.0.1:<port>` in the guest
to `127.0.0.1:<port>` on the host, for each configured port. With the shipped
default (`defaults/ports` empty) there is **no** such channel and host loopback
is fully closed. When ports are configured, any host service bound to a
forwarded loopback port is reachable from `offbox` with the same trust as the
tool the port was opened for. This is SPEC-sanctioned, not a violation.

### Mounts and namespaces

`podman inspect` of the live `offbox` container:

- `…/volumes/<proj>.offbox.worktree/_data → /working/<proj>` `RW=true` (**volume**, a copy — not the host tree)
- `…/volumes/<proj>.offbox.gitdir/_data → /working/<proj>/.git` `RW=true` (**volume**)
- `~/.local/share/opencode/auth.json → …` `RW=false` (read-only host file, declared read mount)
- `<proj>/.git → /host/git` `RW=false` (read-only)
- `lib/merge.sh`, `image/setup.sh`, `defaults/dotfiles` → all `RW=false`

No writable host bind-mount exists. Namespaces: `PidMode=private`, own network
namespace (`talkbox0`), `IpcMode=shareable` (its own IPC namespace, not the
host's). No `--pid=host`, `--ipc=host`, or `--net=host`. This matches SPEC:
"offbox … is never given write access to the host system."

## Hardening observations

None of these is a breach of the isolation SPEC promises; all are
defense-in-depth.

1. **Single-layered egress control (highest priority).** Internet/host-IP
   isolation depends *entirely* on the guest having no non-loopback route,
   which depends on `-i lo` plus `CAP_NET_ADMIN` being dropped. Unlike
   `onbox`/`netbox`, `offbox` gets **no `nftables` backstop** — `deny_allow_args`
   is only invoked for `netbox` in `sandbox_action`
   ([talkbox.sh](talkbox.sh)), and `run_offbox` installs no rules. If any future
   change or podman default reintroduced a gateway or default route (e.g. `-i`
   pointing at a real interface, or a containers.conf change), `offbox` would
   *immediately* gain host-loopback (via the injected `--map-guest-addr
   169.254.1.2` / `--map-host-loopback`) and likely internet, with nothing to
   catch it. **Recommendation:** install a default-drop egress `nftables`
   ruleset in the `offbox` netns too (allow loopback only), mirroring the
   `netbox` path, as a second independent layer.

2. **Host resolver leaked into `offbox`.** `/etc/resolv.conf` inside `offbox`
   contains the host's real upstream DNS server (`185.12.64.2`) rather than a
   fixed forwarder. It is harmless today (unreachable), but it is (a) an
   information leak about the host's network and (b) a ready-made exfil target
   the instant any route appears. **Recommendation:** neutralize resolv.conf for
   `offbox` (e.g. empty it, or point it at a blackholed loopback address).

3. **The `--port` channel is real host access.** Operators must treat every
   forwarded port as exposing that host-loopback service to `offbox` code with
   full trust. Forward only the intended LLM/tool ports; never a port shared
   with a sensitive host daemon. Consider documenting this boundary in the admin
   guide.

4. **Design-inherent data exposure.** `offbox` can *read* host secrets via
   declared read mounts (`auth.json`) and the entire host `.git` via
   `/host/git`. It cannot exfiltrate them over the network (no internet), but it
   *can* copy them into the worktree/gitdir volumes, which a user may later sync
   to the host repo via the bundle workflow. This is spec-sanctioned mount
   behavior, noted for completeness.

5. **`sudo NOPASSWD:ALL`.** Full container-root broadens the in-container attack
   surface if a coding agent is compromised. It does not yield host or internet
   access (bounding caps hold, root maps to an unprivileged host sub-uid), but
   removing it would reduce blast radius.

## Reproduction summary

1. `offbox -c --noninteractive '<probe>'` creates and enters the container.
2. Probes used `python3` (in the base image; `ip`/`iproute2` is not installed)
   and `/proc/net/{route,fib_trie,if_inet6,ipv6_route}` to read the netns state,
   plus `socket.connect()` for reachability and a raw netlink `RTM_NEWROUTE` for
   the route-injection attempt.
3. A host-side marker (`127.0.0.1:54321`) provided unambiguous detection of any
   host-loopback leak.
4. All test containers/volumes/images (`testproj.*`) were removed afterward; the
   shared base image and pre-existing project containers were left untouched.
