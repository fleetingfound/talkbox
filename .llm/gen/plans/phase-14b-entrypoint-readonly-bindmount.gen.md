# Phase 14b: Read-only bind-mount the entrypoint from the host

#flow/redgreen #model/default

## Summary

Implements Option F of
[review: entrypoint-before-nft ordering](../reviews/entrypoint-before-nft-ordering.gen.md):
replace the image-layer `COPY` of `entrypoint.sh` (which is shadowed by the
container's writable layer and thus `sudo`-overwriteable) with a read-only bind
mount of the host file at create time, applied in the three persistent
planners. This closes the in-container tampering vector (direct write returns
`EROFS`; `mount -o remount,rw` fails without `CAP_SYS_ADMIN`) and neutralises
the `podman commit` propagation vector (bind-mount content is excluded from
committed root images). The existing `COPY --chmod=755 entrypoint.sh
/usr/local/bin/entrypoint.sh` in the Containerfile is **retained** as a
defence-in-depth fallback so the image layer always carries a trusted
entrypoint. This is the first of two phases resolving
[issue: agent-modified entrypoint runs before nft deny enforcement](../issues/agent-modified-entrypoint-pre-nft.gen.md);
the second phase ([Phase 14c](phase-14c-nft-before-entrypoint-setup.gen.md))
addresses the pre-nft ordering of the trusted entrypoint body itself.

## Choice documents

This plan implements Option F as described in the review; no choice document is
required (the review's recommendation is adopted directly per the user's
instruction).

## Aspects of the specification implemented

- `SPEC.md` L196-198 (dotfiles / `entrypoint.sh` on `PATH`): the read-only bind
  mount shadows the image-layer copy at runtime with the current trusted host
  file, satisfying both "entrypoint.sh copies dotfiles into `/home/dev/`" and
  "entrypoint.sh is on `PATH` inside the containers" without contract change.
- No SPEC wording change is required.

## Aspects deferred

- The pre-nft ordering of the trusted entrypoint body itself (Option B of the
  review) is deferred to [Phase 14c](phase-14c-nft-before-entrypoint-setup.gen.md).
- Narrowing `NOPASSWD:ALL` sudo (Option C of the review) is deferred.
- The host-side source tampering surface when talkbox itself is the working repo
  mounted read-write in an `onbox` container (the `:ro` mount only blocks writes
  *through that mount*; the same inode written through the `/working/` rw mount
  remains visible) is documented in the review as a narrow case and is not
  addressed here.

## External-facing functionality

- No user-visible behaviour change for the trusted path: containers start and
  run `entrypoint.sh` exactly as before. The only observable difference is that
  `/usr/local/bin/entrypoint.sh` is now a read-only bind mount rather than an
  image-layer file.
- An agent (or any code run by an agent) inside an `onbox`/`netbox`/`offbox`
  container can no longer overwrite `/usr/local/bin/entrypoint.sh`: writes
  return `EROFS` (Read-only file system), even via `sudo`, and `mount -o
  remount,rw` fails (no `CAP_SYS_ADMIN`).
- `podman commit` of a container whose entrypoint is the bind mount no longer
  persists a potentially-tampered entrypoint into the committed root image; the
  committed image gets the original image-layer `COPY` (trusted) at that path.
  `--recontain`/`--rebuild` for netbox/offbox therefore always run the trusted
  entrypoint.

## Files to be created

None.

## Files to be modified

- [`lib/containers.sh`](../../../lib/containers.sh) — the three persistent
  planners:
  - `plan_onbox` (~L73-108): add a `-v
    "$TALKBOX_ROOT/image/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro"` entry
    to the plan array, alongside the existing `:ro` bind mounts for
    `lib/merge.sh` and `defaults/dotfiles`. Place it near those mounts for
    consistency.
  - `plan_netbox` (~L353-403): same addition.
  - `plan_offbox` (~L405-455): same addition.
  - The `:Z` relabel flag is included only if the existing `:ro` mounts in the
    same planner use it; currently they do not (e.g. `merge.sh:ro`), so follow
    that convention (omit `:Z`). The implementing agent should verify against
    the existing mount style in each planner and match it.
- [`image/Containerfile`](../../../image/Containerfile) — **no change**: the
  existing `COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh` (L25)
  is retained as the defence-in-depth fallback. A code comment is not added per
  repo convention.

## Relevant files to read during implementation

- [`lib/containers.sh`](../../../lib/containers.sh) (`plan_onbox` L59-108,
  `plan_netbox` L353-403, `plan_offbox` L405-455) — the existing `:ro` bind
  mount pattern (`-v "$TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro"` at
  L90/L385/L437; `-v "$TALKBOX_ROOT/defaults/dotfiles:..."` at L94/L389/L441).
- [`image/Containerfile`](../../../image/Containerfile) (L25 the `COPY`, L35 the
  `ENTRYPOINT`).
- [`image/entrypoint.sh`](../../../image/entrypoint.sh).
- [`test/unit/containers.bats`](../../../test/unit/containers.bats) — existing
  mount-assertion pattern (`array_contains "$TALKBOX_ROOT/defaults/dotfiles:...ro"`
  at L109/L117).
- [`test/unit/netbox-offbox.bats`](../../../test/unit/netbox-offbox.bats) —
  existing mount-assertion pattern (L193).
- [`test/e2e/deny-allow.bats`](../../../test/e2e/deny-allow.bats) — e2e harness
  and `require_nft_and_internet` guard.
- [`test/e2e/onbox.bats`](../../../test/e2e/onbox.bats) — onbox e2e patterns.

## Key internal interfaces

- `plan_onbox`/`plan_netbox`/`plan_offbox` — each gains one array entry
  appending the read-only bind mount of the host entrypoint to
  `/usr/local/bin/entrypoint.sh`. No signature change. The mount is appended in
  the same block as the other `TALKBOX_ROOT`-sourced `:ro` mounts so the
  ordering of mounts in the plan stays grouped.
- No new functions or public interface changes.

## Tests

This phase requires tests. The redgreen first subagent adds failing tests; the
second implements the bind mount so they pass.

### Unit tests — `test/unit/containers.bats` and `test/unit/netbox-offbox.bats`

Following the existing `array_contains` mount-assertion pattern (e.g.
`containers.bats:109`):

- `plan_onbox` emits a `-v
  "$TALKBOX_ROOT/image/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro"` entry.
- `plan_netbox` emits the same mount.
- `plan_offbox` emits the same mount.
- `plan_recontain` (onbox) propagates the mount to the `podman create` args
  (mirrors the existing tmpfs-propagation test pattern at `containers.bats:356`).
- `plan_rebuild` (onbox) propagates the mount (mirrors `containers.bats:364`).
- The netbox/offbox `recontain`/`rebuild` plans propagate the mount (mirrors the
  netbox-offbox tmpfs-propagation tests at L491/L500/L509/L518).

### End-to-end tests — `test/e2e/deny-allow.bats` or `test/e2e/onbox.bats`

- An onbox (or netbox) e2e test asserting that an attempt to overwrite
  `/usr/local/bin/entrypoint.sh` from inside the container (as `dev`, including
  via `sudo tee`) fails with a read-only-filesystem error, and that the file's
  contents remain the trusted entrypoint. This validates the empirical
  `EROFS`/remount-failure claims in the review against the real container.
- A netbox `--recontain` (or `--rebuild`) e2e test asserting that after a
  `podman commit`-derived root image is created, the entrypoint in the
  resulting container is the trusted entrypoint (not an empty stub and not a
  tampered file) — i.e. the ro bind mount is re-applied on the recreated
  container and the committed image did not capture a tampered entrypoint. This
  may be combined with the tampering-attempt test (attempt to tamper in the
  source container, then `--recontain` the inheriting container and verify its
  entrypoint is still the trusted file).
- These e2e tests are gated behind the existing skip guards
  (`require_nft_and_internet` where a running onbox/netbox is needed) or a
  podman-availability guard as appropriate.

## Issue resolution

This phase closes the **tampering vector** portion of
[issue: agent-modified entrypoint runs before nft deny enforcement](../issues/agent-modified-entrypoint-pre-nft.gen.md):
the in-container overwrite route and the `podman commit` propagation route are
both neutralised. The issue is **not** marked complete in
[`.llm/gen/issues/INDEX.gen.md`](../issues/INDEX.gen.md) until
[Phase 14c](phase-14c-nft-before-entrypoint-setup.gen.md) also lands (the
pre-nft ordering of the trusted entrypoint body remains open until then).
