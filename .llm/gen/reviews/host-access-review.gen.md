# Host-access security review (netbox container)

**Scope.** Determine whether this container can access the host in a manner
forbidden by [SPEC.md](SPEC.md) — specifically whether a `netbox` container can
gain **write access to the host** or read host state beyond its declared
read-only mounts. Review combines static analysis of the implementation with
read-only observation of the live container. Where noted, live exploitation was
constrained by the runtime safety layer; those vectors were instead confirmed
non-viable by capability and mount inspection.

**Verdict.** No host-access violation of SPEC.md was found. Every host-backed
mount in the running container is read-only; the only writable mounts are
podman-managed volumes and the container's own overlay. In-container privilege
escalation is available (`sudo`) but confined to a user namespace whose
capability bounding set lacks `CAP_SYS_ADMIN`, and whose root maps to an
unprivileged host sub-uid. Several **hardening observations** and
**design-inherent data-exposure** points are recorded below; none is a breach of
the isolation the spec promises.

## Environment observed

This is the `netbox` container for project `talkbox.security-test4`.

- User `dev`, `uid=1000(dev) gid=1000(dev)`, no supplementary groups.
- `CapEff=0000000000000000` (zero effective capabilities as `dev`).
- `CapBnd=00000000800405fb` → bounding set = `CHOWN, DAC_OVERRIDE, FOWNER,
  FSETID, KILL, SETGID, SETUID, SETPCAP, NET_BIND_SERVICE, SYS_CHROOT, SETFCAP`.
  **No** `SYS_ADMIN`, `MKNOD`, `SYS_PTRACE`, `NET_ADMIN`, `NET_RAW`,
  `SYS_MODULE`.
- `Seccomp: 2` (filtered), `Seccomp_filters: 1`.
- `userns` map: container `uid 1000` → host user (the rootless podman runner);
  container `uid 0` → an unprivileged host sub-uid.
- No container-runtime socket present (`/run/podman`, `/run/docker.sock`, etc.
  all absent).

## Filesystem isolation — PASS

Enumerating `/proc/self/mountinfo` and classifying every mount:

| Mountpoint | Backing | Mode |
|---|---|---|
| `/working/talkbox.security-test4` | volume `…netbox.worktree` | **rw (volume)** |
| `/working/talkbox.security-test4/.git` | volume `…netbox.gitdir` | **rw (volume)** |
| `/` | overlay (container layer) | rw (ephemeral) |
| `/dev/console` | devpts | rw (tty) |
| `/host/git` | host `…/talkbox.security-test4/.git` | **ro** |
| `/talkbox/dotfiles.global` | host `…/talkbox/defaults/dotfiles` | **ro** |
| `/talkbox/lib/merge.sh` | host `…/talkbox/lib/merge.sh` | **ro** |
| `/usr/local/bin/setup.sh` | host `…/talkbox/image/setup.sh` | **ro** |
| `/home/dev/.local/share/opencode/auth.json` | host `…/opencode/auth.json` | **ro** |
| `/run/podman-init` | host `catatonit` | **ro** |

There is **no writable mount whose backing is a host path**. This matches
SPEC.md §netbox: "Every mount it receives is either a read-only bind-mount or a
volume." The implementation enforces this in code: for `netbox`/`offbox`,
`sandbox_action` builds write mounts via `mount_volume_args`
([lib/mounts.sh](lib/mounts.sh):117) which emits `-v <volume>:<dest>` named
volumes, never host bind mounts; only `onbox` uses rw host binds
([lib/mounts.sh](lib/mounts.sh):108, `mount_args` write mode). Read mounts always
receive `:ro` ([lib/mounts.sh](lib/mounts.sh):109). `plan_netbox`
([lib/containers.sh](lib/containers.sh):364) hard-codes `/host/git`,
`merge.sh`, `setup.sh`, and dotfiles as `:ro` and consumes the volume-based
write list.

The two writable volumes are podman's own storage (backed under
`~/.local/share/containers/storage/volumes/`), which is the sanctioned RW target
per spec, not "the host system" the spec protects (the working tree and private
host data). Changes there reach the host only through the audited git-bundle
channel (below).

## In-container privilege escalation — PASS (contained)

The base image grants `dev` passwordless sudo
([image/Containerfile](image/Containerfile):15,37-41). `sudo id` succeeds
(`uid=0(root)`), but:

- container-root is still inside the same user namespace, whose bounding set has
  **no `CAP_SYS_ADMIN`** — so it cannot `mount`/remount the read-only host binds,
  cannot `pivot_root`/`unshare -m` into a usable new mount tree over locked
  mounts, and cannot create device nodes (`no CAP_MKNOD`) to reach host block
  devices;
- container-root maps to an **unprivileged host sub-uid**, so any file it could
  create is owned by a throwaway sub-uid on the host, not the invoking user and
  not real root — a *reduction* in host authority versus `dev` (which maps to the
  runner).

Consequently the sudo grant does not translate into host access. It is
nonetheless unnecessary attack surface (see hardening notes).

## Container-runtime access — PASS

No podman/docker socket is mounted, and the CLI binaries are absent from the
container (`command -v podman docker` → none; only `nsenter` exists). The classic
"talk to the runtime socket and create a `-v /:/host` container" escape is not
available. The host-side orchestrator invokes podman only from the host.

## Git transport (host-side `fetch`/`merge`/`sync`) — PASS

This is the only channel by which container-authored data reaches the host, so it
is the highest-value logical surface. The container fully controls the `netbox`
gitdir/worktree volumes; the host operator later runs `netbox fetch|merge|sync`.

- **Bundle export** ([lib/git.sh](lib/git.sh):98) runs
  `podman run --rm --network=none` with the gitdir volume `:ro` and only the host
  temp-bundle dir writable, producing a bundle with `git bundle create --all`.
  Isolated (no network) and cannot write outside the temp dir.
- **Host fetch** ([lib/git.sh](lib/git.sh):109) is
  `git fetch <bundle> +refs/heads/*:refs/remotes/<container>/*` — container refs
  land only under `refs/remotes/<container>/`.
- **`custom_merge`** ([lib/merge.sh](lib/merge.sh):28) advances host branches with
  `git merge --ff-only`, `git reset --mixed`, or `git branch -f`. Branch names
  (attacker-influenced, since they originate from container refs) are passed as
  **argv**, never `eval`-ed; git's own refname validation blocks `..`/path
  traversal. No hooks execute on the host: the host `.git` is read-only to the
  container, so a malicious container cannot plant a host-side hook, and
  fast-forward/reset do not run container-supplied hooks.
- For `netbox`, `custom_merge` runs against the **host** worktree and **host**
  `.git`, neither of which the container can modify (worktree is a volume copy;
  host `.git` is RO). So host-side `git add -A` in `worktree_matches_tree`
  ([lib/merge.sh](lib/merge.sh):46) can only honor filters/`fsmonitor` defined in
  host-trusted content, not container-injected content.
- **`sync`** ([lib/git.sh](lib/git.sh):231) runs *inside* a container (or a
  `--network=none` temp container mounting host `.git` `:ro`), modifying only
  container git state.

No command-injection or host-write path was found in this channel.

## Volume population helpers — PASS

`plan_volume_populate` ([lib/containers.sh](lib/containers.sh):350) — used to seed
netbox/offbox worktree and write volumes — runs `podman run --network=none`, and
when the source is a **host** path it is mounted `:ro` (`…/source:ro`), matching
SPEC.md §implementation ("the host source must be mounted read-only", "created
without any network access"). Only the target volume is writable.

## Network posture — matches spec (host reachability limited by design)

- `netbox` network string is
  `pasta:[-T,<port>…],--dns-forward,169.254.1.1,--map-guest-addr,none` with
  `--cap-drop=NET_ADMIN --cap-drop=NET_RAW` ([lib/containers.sh](lib/containers.sh):364).
  `--map-guest-addr,none` removes pasta's host-gateway mapping, so the container
  reaches the host **only** on explicitly forwarded `-T` ports. `defaults/ports`
  is empty here, so this container forwards no host ports.
- Egress IP denial is applied from the **host** side via
  `podman unshare nsenter -t <pid> -n nft -f -` ([lib/network.sh](lib/network.sh):129),
  i.e. inside the container's netns but from outside its control; with
  `NET_ADMIN` dropped the container cannot flush these rules.
  `defaults/deny.ip` blocks RFC-1918, CGNAT, and link-local **169.254.0.0/16
  (cloud metadata)**; loopback and the `169.254.1.1` DNS forwarder are
  unconditionally allowed ([lib/network.sh](lib/network.sh):58). This is a sound
  anti-SSRF posture.
- `offbox` uses `pasta:[-T,…],-i,lo,-I,talkbox0` with no `--dns-forward`,
  removing general egress while retaining loopback + explicit host ports —
  consistent with the spec's "disable internet" requirement.

## Hardening observations (not spec violations)

1. **Passwordless `sudo` in the base image** ([image/Containerfile](image/Containerfile):15,37-41).
   Contained by the user namespace as shown, but it is avoidable attack surface
   and would matter immediately if the container were ever run with a wider
   userns or added capabilities. Recommend removing `sudo` from the image unless a
   concrete need exists.
2. **Host secret exposed read-only + internet egress.** `defaults/read.mounts`
   maps `~/.local/share/opencode/auth.json` into every container read-only. In
   `onbox`/`netbox` (internet-enabled), any code in the sandbox can read and
   exfiltrate this credential. This is a deliberate design trade-off (the spec
   uses it as the canonical example), but it is worth calling out against the
   stated goal of "protecting private data": the guarantee is *integrity* of the
   host, not *confidentiality* of whatever is mounted in.
3. **Full host git history is readable** via `/host/git` (RO). Intended as
   transport, but it exposes all committed objects/branches (including anything
   sensitive ever committed) to sandbox code. Read-only, so no tampering.
4. **`TALKBOX_STRICT_NFT=0` downgrades enforcement.** In lax mode
   ([lib/network.sh](lib/network.sh):138) a failure to apply the nft deny ruleset
   only warns and proceeds, leaving egress unfiltered. Default (strict) fails
   closed and stops the container — keep the default in any real deployment.

## Vectors that could not be exercised live

The runtime safety layer blocked active escape attempts (writing to a read-only
host mount, `mount -o remount,rw`, `unshare -m`). These were therefore not
executed end-to-end. However, each is independently established as non-viable by
the observations above: `CapEff=0` and a bounding set without `CAP_SYS_ADMIN`
mean remount/mount fail with `EPERM`; the host binds are `MS_RDONLY` and locked
by podman; and there is no host-backed writable mount to target in the first
place. No path was identified — statically or observationally — by which this
`netbox` container obtains write access to the host filesystem.

## Conclusion

The `netbox` container upholds SPEC.md's central guarantee: it is never given
write access to the host, and every host-backed mount is read-only. Runtime
containment (zero effective caps, restricted bounding set, seccomp, dropped
`NET_ADMIN`/`NET_RAW`, `--map-guest-addr,none`, no runtime socket) and the
host-side tooling (argv-only refname handling, RO host `.git`, `--network=none`
helpers with RO host sources) are mutually reinforcing. The findings above are
hardening and confidentiality trade-offs, not violations of the host-access
boundary the specification defines.
