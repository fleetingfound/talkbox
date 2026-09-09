# Entrypoint-before-nft ordering and agent-modified entrypoint risk

## Summary

`image/entrypoint.sh` runs inside the container (as `dev`, uid 1000) immediately
on `podman start`, while the nftables deny/allow ruleset is applied **from the
host** only after `wait_for_entrypoint` reports the `/run/talkbox/ready`
sentinel. This creates a window in which the container has full network access
(onbox/netbox) with the deny list unenforced, and — more seriously — exposes a
persistent tampering vector: an agent running in the container can modify
`/usr/local/bin/entrypoint.sh`, and the modified script will run *before* the nft
rules are installed on every subsequent start of that container (and can be
propagated into inherited root images via `podman commit`).

## Startup ordering (current)

For `onbox`/`netbox` ([lib/containers.sh](../../../lib/containers.sh) `run_onbox`
~L215, `run_netbox` ~L685):

1. `podman start "$ctr"`
2. `wait_for_entrypoint "$ctr"` — polls for `/run/talkbox/ready`
3. `install_nft_deny_or_die "$ctr" ...` — host enters the container netns via
   `podman unshare nsenter -t <PID> -n nft -f -` ([lib/network.sh](../../../lib/network.sh) `plan_nft_deny` L131)
4. `podman exec` the user command

`entrypoint.sh` ([image/entrypoint.sh](../../../image/entrypoint.sh)) runs as
`dev` between steps 1 and 2: copies dotfiles, writes git config, initialises the
gitdir volume, writes the sentinel, then `exec bash -c "sleep infinity"`.

`offbox` skips `install_nft_deny_or_die` entirely (no internet path), so the
ordering concern is specific to `onbox`/`netbox`.

## Security implications of the pre-nft window

### What runs in the window

The entrypoint itself does not issue outbound network calls: `git fetch host`
targets the bind-mounted local path `/host/git/`, not a network remote. So the
*current* entrypoint body is not an exfiltration vector on its own. The
implications are nevertheless real because of what holds during the window:

- **Network is unrestricted.** The container is attached to `pasta` with the
  onbox/netbox outbound configuration and **no deny set enforced**. Any process
  spawned by the entrypoint (or surviving from it) can reach any IP that `pasta`
  will route, including every address in `defaults/deny.ip`.
- **`dev` has `NOPASSWD:ALL` sudo** ([image/Containerfile](../../../image/Containerfile) L21).
  The entrypoint already uses `sudo -n touch` for the sentinel (L38) because
  `/run/talkbox` is root-owned after restart/commit. This means the entrypoint —
  and anything it launches — can escalate to root inside the container during the
  window. Root inside the container cannot bypass the netns-level nft rules once
  applied (the container has `--cap-drop=NET_ADMIN`/`NET_RAW`), but **before**
  the rules exist there is nothing to bypass.
- **The window is bounded by the sentinel, not by nft.** `wait_for_entrypoint`
  returns as soon as `/run/talkbox/ready` exists; the entrypoint writes the
  sentinel as its *last* action before `exec`. So the window is roughly
  "entrypoint body duration + poll latency", typically sub-second to a few
  seconds, but unbounded if the entrypoint blocks (e.g. a slow `git fetch host`).

### The real concern is not the current entrypoint body, but tampering

The window is benign *only if the entrypoint is the trusted image contents*. The
threat surface expands dramatically once an agent (or any code the agent runs)
can alter the entrypoint, because the altered script is what runs in the window
on every subsequent start. See the linked issue for the full analysis.

## Risk of an agent-modified `entrypoint.sh` being called before nft

➡️ See [issue: agent-modified entrypoint runs before nft deny enforcement](../issues/agent-modified-entrypoint-pre-nft.gen.md)
for the concise problem statement. The mechanics are summarised here.

### Three modification surfaces

1. **In-container copy at `/usr/local/bin/entrypoint.sh`.** Baked into the image
   by `COPY --chmod=755` ([image/Containerfile](../../../image/Containerfile) L25),
   root-owned, mode `0755`. `dev` cannot write to it directly, but `dev` has
   `NOPASSWD:ALL` sudo, so `sudo tee /usr/local/bin/entrypoint.sh` suffices. The
   modification lands in the container's writable layer (copy-on-write) and
   overrides the image-layer file for **that container only**.

2. **Propagation via `podman commit` (netbox/offbox inheritance).**
   [lib/containers.sh](../../../lib/containers.sh) `create_netbox` (L646),
   `create_offbox` (L669), `plan_netbox_recontain` (L467),
   `plan_offbox_recontain` (L492), `plan_netbox_rebuild` (L518),
   `plan_offbox_rebuild` (L544) all run
   `podman commit "$(container_name_of "$source" "$project")" "$root"` when the
   inheritance source is not `base`. `podman commit` captures the container's
   writable layer, **including a modified `/usr/local/bin/entrypoint.sh`**, and
   bakes it into the project's root image (`<project-slug>.<container>.root`).
   The modified entrypoint then runs on every start of containers created from
   that root image, and is itself inherited further down the chain
   (onbox → netbox → offbox). `--recontain`/`--rebuild` therefore do **not**
   reliably remediate the tampering for netbox/offbox: they recreate the
   container from a committed root image that may already carry the
   modification.

3. **Host-side source at `image/entrypoint.sh`.** For `onbox`, `<project>/` is
   mounted read-write into the container (`/working/<base>`) per SPEC ("allows
   direct edits to `<project>/`"). If `image/entrypoint.sh` is tracked inside
   `<project>/`, an agent in an `onbox` container can edit the host copy, and the
   modification is picked up by the next `--rebuild` (which runs
   `podman build -f $TALKBOX_ROOT/image/Containerfile $TALKBOX_ROOT/image`).
   Whether this surface exists depends on whether the talkbox repository itself
   is the working repo or installed elsewhere; when talkbox is installed as a
   tool and `<project>/` is a separate repo, this path is not reachable from the
   container.

### Attack scenario

1. Agent (or a tool it runs) in an `onbox`/`netbox` container escalates via
   `sudo` and overwrites `/usr/local/bin/entrypoint.sh`.
2. The user stops the container (shell exits or `-c` command finishes).
3. The user starts the container again with a plain `onbox`/`netbox` (no
   `--recontain`/`--rebuild`): the **modified** entrypoint runs.
4. The modified entrypoint executes *before* `install_nft_deny_or_die`. It can:
   - open outbound connections to denied IPs and exfiltrate the working tree,
     dotfiles, or git history during the window;
   - write `/run/talkbox/ready` immediately so `wait_for_entrypoint` returns
   fast, then continue malicious work in a backgrounded process that persists
   across the nft install (the nft rules drop *new* outbound matches; they do
   not kill existing connections or processes);
   - alter the environment (e.g. swap binaries on `PATH`, install hooks, modify
   `~/.gitconfig`, plant a `.bashrc`) that affects the subsequent user `podman
   exec` even after nft is applied.
5. If the container is later used as an inheritance source for netbox/offbox,
   `podman commit` persists the modified entrypoint into the root image, so the
   tamper survives `--recontain`/`--rebuild` for those containers.

### Why the existing fail-hard semantics do not address this

`install_nft_deny` fails hard by default (`TALKBOX_STRICT_NFT` unset/nonzero,
[.llm/gen/choices/ip-deny-allow-enforcement.gen.md](../choices/ip-deny-allow-enforcement.gen.md)
L45) and stops the container if the rules cannot be applied. But the threat
here is not "rules failed to apply" — it is "the rules were applied correctly,
*after* untrusted code already ran in the window". The fail-hard path has no
visibility into whether the entrypoint was tampered with.

## Alternate designs

### A. Install nft before the entrypoint runs (pre-created netns)

Create and own the network namespace before the container starts, install the
nft ruleset there, then attach the container with `--network=ns:/proc/<PID>/ns/net`.
This is **Option D** of
[ip-deny-allow-enforcement](../choices/ip-deny-allow-enforcement.gen.md):
talkbox creates the netns via `unshare -r -n`, runs `pasta` manually, installs
`nft` as root of the userns, and passes the netns to podman. The deny list is
enforced from the first packet the container sends, eliminating the window
entirely. The choice doc rejected it as "out of proportion" for the original
feature, but the tampering risk strengthens the case: it is the only design
that makes the ordering invariant structural rather than temporal.

**Pros:** no pre-nft window by construction; tampered entrypoint still runs, but
never with unrestricted network. **Cons:** large restructure of the networking
delegation to podman's `--network=pasta:` integration; duplicates pasta
lifecycle management.

### B. Move entrypoint setup into a host-driven `podman exec` after nft install

This is **Option D** of
[entrypoint-readiness-sync](../choices/entrypoint-readiness-sync.gen.md): the
image `ENTRYPOINT` becomes trivial (`exec sleep infinity`), and the setup
(dotfiles, git config, gitdir init) is run by the executor via `podman exec`
**after** `install_nft_deny_or_die`. The ordering becomes:

1. `podman start` (trivial entrypoint, no privileged work)
2. `install_nft_deny_or_die`
3. `podman exec` setup script
4. `podman exec` user command

This removes the sentinel/poll mechanism entirely and guarantees setup runs
under the deny list. It does **not** by itself prevent an agent from modifying
the setup script (still root-owned, still sudo-reachable), but it means the
*trusted* setup never runs unguarded, and a tampered setup script would run
under nft enforcement. The choice doc flagged a SPEC contract change ("Whenever
one of these containers starts, the script `entrypoint.sh` copies these…") and
`podman commit` timing concerns; both are real but tractable (the SPEC wording
can be updated, and commit captures filesystem state regardless of whether
setup ran via ENTRYPOINT or exec).

**Pros:** eliminates the window for the trusted setup path with no netns
restructure; aligns ordering with the threat model. **Cons:** SPEC contract
change; `--recontain`/`--rebuild` must also run the setup exec; one-shot
`podman run --rm` containers (which rely on the ENTRYPOINT running the command)
need a separate path.

### C. Make the entrypoint integrity-verifiable / immutable

Keep the current ordering but add a defence: before `wait_for_entrypoint`
returns (or before `podman exec`), the executor verifies that
`/usr/local/bin/entrypoint.sh` in the container matches a known hash captured
at image-build time. Mismatch aborts the start. This detects tampering of the
in-container copy but does nothing for the host-side source file, and adds a
hash-management burden (the hash must be stored outside the container's
writable layer, e.g. baked into the image label or a host-side file).

A weaker variant: drop `NOPASSWD:ALL` sudo from the image and grant `dev` only
a narrowly-scoped sudoers rule for the sentinel touch (or move the sentinel to
a `dev`-writable location so no sudo is needed at all). This removes the
trivial root escalation that makes overwriting the root-owned entrypoint a
one-liner. It does not stop a container compromise that finds another
escalation path, but it shrinks the attack surface substantially and is
independently desirable (the broad sudo exists today only as a workaround for
the `/run/talkbox` permissions).

**Pros:** localised; pairs naturally with B. **Cons:** hash scheme is a new
moving part; narrowing sudo alone does not close the window, only the easiest
tampering route.

### D. Recreate the container on every run (no reuse)

Always run as if `--recontain` were set, so the container is created fresh from
the (trusted) image each time and no modified writable layer persists. This
trivially defeats in-container tampering of the entrypoint but defeats much of
the point of persistent containers (state, installed packages, agent session
continuity) and is expensive. It also does not help netbox/offbox when the root
image itself was committed from a tampered source container.

**Pros:** simple invariant. **Cons:** discards container state; costly; does
not address committed-root-image propagation.

### E. Apply nft earlier in the same start sequence without restructuring

A narrower tweak: run `install_nft_deny_or_die` *before* `wait_for_entrypoint`
(as soon as `podman inspect` yields a PID). The container netns exists from the
moment `podman start` returns, so the rules can be installed before the
entrypoint reaches the sentinel. This shrinks the window to "time between
`podman start` returning and the entrypoint's first instruction" — but that is
still non-zero, still contains the entrypoint's first actions (dotfiles copy,
git config), and still runs the (possibly tampered) entrypoint. It is an
amortisation, not a closure, and it introduces a race between the host-side nft
install and the entrypoint's first packet.

**Pros:** minimal change. **Cons:** does not close the window; adds a race;
still trusts the entrypoint.

### F. Read-only bind-mount the entrypoint from the host

Replace the image-layer `COPY` of `entrypoint.sh` (which is shadowed by the
container's writable layer and thus `sudo`-overwriteable) with a read-only bind
mount of the host file at create time:

```
-v "$TALKBOX_ROOT/image/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro,Z"
```

This mirrors the existing convention already used for `$TALKBOX_ROOT/lib/merge.sh`
and `$TALKBOX_ROOT/defaults/dotfiles` (both bind-mounted `:ro` in the three
persistent planners, [lib/containers.sh](../../../lib/containers.sh) L90/L94/L97,
L385/L389/L392, L437/L441/L444).

**Validated empirically against the two tampering routes:**

1. **Direct overwrite fails.** Even as root inside the container, writing to the
   mount returns `EROFS` (Read-only file system). `sudo tee` is no longer a
   one-liner escape.
2. **`mount -o remount,rw` fails.** Remounting a read-only bind mount requires
   `CAP_SYS_ADMIN`, which is **not** in rootless podman's default capability
   set (the bounding set decodes to `0x800405fb`, which has no bit 20). talkbox
   only drops `NET_ADMIN`/`NET_RAW` on top of the defaults, so `SYS_ADMIN`
   remains absent and the mount cannot be remounted writable by the container,
   even via `sudo`.
3. **`podman commit` does not capture bind-mount content.** A committed root
   image gets an empty stub at the mount path (or, if the `COPY` is retained in
   the Containerfile, the original image-layer file) — **never** the bind-mounted
   host file. The inheritance-propagation vector
   ([lib/containers.sh](../../../lib/containers.sh) `podman commit` at L646/L669/
   L467/L492/L518/L544) is therefore neutralised for the entrypoint: a tampered
   entrypoint cannot be baked into a netbox/offbox root image via commit, and as
   long as the planner re-applies the `:ro` bind mount on every create, every
   container always runs the trusted host entrypoint.

**What it does and does not close:**

- ✅ Closes the in-container tampering vector (overwrite `/usr/local/bin/entrypoint.sh`).
- ✅ Closes the `podman commit` propagation vector (bind-mount content excluded
  from committed images).
- ❌ Does **not** close the pre-nft window for the *trusted* entrypoint body
  itself: the trusted entrypoint still runs before nft, so if the threat model
  includes "the trusted entrypoint is buggy or triggers untrusted code"
  (e.g. a planted `.bashrc` in `/home/dev/`, a git hook in the gitdir volume),
  that code still runs unguarded. To close the window for the trusted path,
  combine with **B** (move setup post-nft) or **A** (pre-created netns).
- ❌ Does **not** protect the host-side source file when talkbox itself is the
  working repo mounted read-write in an `onbox` container (`/working/<base>/image/
  entrypoint.sh` is the same inode as the bind-mount source). A `:ro` mount only
  blocks writes *through that mount*; the same file written through the separate
  `/working/` rw mount is still visible through the ro mount. This is a narrow
  case (talkbox installed as a tool with `<project>` separate is unaffected, as
  `$TALKBOX_ROOT` is outside the container's reach), but it means F alone is not
  a complete defence when talkbox sandboxes itself.

**Retain the `COPY` in the Containerfile.** Keeping the existing `COPY
--chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh` alongside the bind mount
gives a defence-in-depth fallback: the image layer always carries a valid
trusted entrypoint, and the ro bind mount shadows it at runtime with the current
host file. If a planner bug ever omits the bind mount, the container falls back
to the image-layer copy rather than an empty stub.

**Pros:** smallest possible change (one `-v` line per planner, following the
existing `:ro` mount convention); empirically robust against both write and
remount; neutralises the commit-propagation vector for free; no SPEC contract
change; no netns restructure. **Cons:** does not close the pre-nft window for
the trusted entrypoint; host-source tampering remains when talkbox is the
working repo; couples runtime to the host `$TALKBOX_ROOT` path (already true for
`merge.sh` and dotfiles, so no new coupling).

## Recommendation

For the **tampering vector specifically** (the question at hand), **F is the
correct, sufficient, and most localised fix.** It directly removes the
agent's ability to alter the entrypoint that runs pre-nft, and it breaks the
`podman commit` propagation chain — both validated empirically — with a single
`-v` line per planner that mirrors conventions already in the codebase. It
should be adopted regardless of any other change.

For the **broader pre-nft window** (trusted-but-misordered code running
unguarded), F does not help and the recommendation remains **B + C**:

- **B** (move setup to a post-nft `podman exec`) removes the window for the
  trusted setup path and aligns the ordering with the threat model.
- **C** (narrow `NOPASSWD:ALL` sudo to the minimum needed, or eliminate it by
  making `/run/talkbox` `dev`-writable) removes the trivial root escalation
  that is the broader attack surface, and is independently justified.

**A** is the only option that makes the ordering invariant structural (rules
present before any container code runs) and should be reconsidered if the
threat model ever needs to defend against a compromised entrypoint running
arbitrary pre-nft code, rather than just a trusted-but-misordered one.

In summary: **adopt F now** (it is cheap, validated, and closes the tampering
vector that prompted this review); treat B+C or A as the follow-on if the
threat model extends to the trusted entrypoint itself.

## Related

- [Issue: agent-modified entrypoint runs before nft deny enforcement](../issues/agent-modified-entrypoint-pre-nft.gen.md)
- [Choice: IP deny/allow enforcement mechanism](../choices/ip-deny-allow-enforcement.gen.md)
- [Choice: Entrypoint readiness synchronization mechanism](../choices/entrypoint-readiness-sync.gen.md)
- [nftables deny/allow install failure — warning, test gap, and fail-hard consideration](nftables-deny-install-warning.gen.md)
- [SPEC.md — design goals, network, git as transport](../../../SPEC.md)
