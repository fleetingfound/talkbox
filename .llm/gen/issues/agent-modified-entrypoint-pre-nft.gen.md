# Agent-modified entrypoint runs before nft deny enforcement

## Summary

`/usr/local/bin/entrypoint.sh` is the container `ENTRYPOINT`
([image/Containerfile](../../../image/Containerfile) L25, L35) and runs as `dev`
on every `podman start`, **before** `install_nft_deny_or_die` applies the nft
deny/allow ruleset from the host
([lib/containers.sh](../../../lib/containers.sh) `run_onbox` L230–231,
`run_netbox` L695–696). An agent running inside an `onbox`/`netbox` container can
modify this file (it is root-owned `0755`, but `dev` has `NOPASSWD:ALL` sudo per
[image/Containerfile](../../../image/Containerfile) L21), and the modified
script will execute on subsequent starts of that container — in the window where
the deny list is not yet enforced. The modification can also be propagated into
netbox/offbox root images via `podman commit`
([lib/containers.sh](../../../lib/containers.sh) L646, L669, L467, L492, L518,
L544), surviving `--recontain`/`--rebuild` for those containers.

## Files causing the issue

- [image/Containerfile](../../../image/Containerfile) — L21 grants `dev
  ALL=(ALL) NOPASSWD:ALL`; L25/L35 make `entrypoint.sh` the immutable-by-image
  ENTRYPOINT.
- [image/entrypoint.sh](../../../image/entrypoint.sh) — runs (as `dev`) before
  nft is applied; uses `sudo -n touch` (L38) for the sentinel, demonstrating
  the sudo path is already active during the window.
- [lib/containers.sh](../../../lib/containers.sh) — `run_onbox` (L229–231) and
  `run_netbox` (L694–696) order `podman start` → `wait_for_entrypoint` →
  `install_nft_deny_or_die`, so the entrypoint body executes before the deny
  list exists in the netns.
- [lib/containers.sh](../../../lib/containers.sh) — `create_netbox` (L646),
  `create_offbox` (L669), `plan_netbox_recontain` (L467),
  `plan_offbox_recontain` (L492), `plan_netbox_rebuild` (L518),
  `plan_offbox_rebuild` (L544) run `podman commit` on the source container,
  persisting any writable-layer modification of `/usr/local/bin/entrypoint.sh`
  into the inherited root image.

## Impact

- A tampered entrypoint can make outbound connections to denied IPs, exfiltrate
  the working tree / dotfiles / git history, and plant environment changes
  (PATH swaps, `.bashrc`/`.gitconfig` modifications) that affect the
  subsequent user command — all before the deny list is enforced.
- Backgrounded processes spawned by the tampered entrypoint persist across the
  nft install (nft drops *new* outbound matches; it does not kill existing
  connections).
- `--recontain`/`--rebuild` do not reliably remediate the tampering for
  netbox/offbox when the committed root image carries the modification.
- The `TALKBOX_STRICT_NFT` fail-hard path does not detect this: it only covers
  "rules failed to apply", not "untrusted code ran before rules were applied".

## Mitigations under consideration

See [review: entrypoint-before-nft ordering and agent-modified entrypoint risk](../reviews/entrypoint-before-nft-ordering.gen.md)
for the full design analysis. The most direct fix for the tampering vector
specifically is **Option F** (read-only bind-mount the entrypoint from the host):
validated empirically to resist both direct write (`EROFS`) and `mount -o
remount,rw` (no `CAP_SYS_ADMIN` in the container bounding set), and to
neutralise the `podman commit` propagation vector (bind-mount content is
excluded from committed images). Broader closures for the pre-nft window of the
trusted entrypoint itself are Option B (move setup to a post-nft `podman exec`,
from [entrypoint-readiness-sync](../choices/entrypoint-readiness-sync.gen.md))
and Option A (pre-created netns, Option D of
[ip-deny-allow-enforcement](../choices/ip-deny-allow-enforcement.gen.md)).
