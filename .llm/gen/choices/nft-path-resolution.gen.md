# nft PATH resolution — auto-handling `nft` not on `PATH`

`nft` is typically installed at `/usr/sbin/nft` (or `/sbin/nft`), which is **not** on a non-root user's `PATH` on stock Debian/Ubuntu/Fedora. With Phase 14a's fail-hard default, this makes `onbox`/`netbox` abort out-of-the-box whenever the (non-empty) stock `defaults/deny.ip` is in effect — even though `nft` is present on the host. The `TALKBOX_STRICT_NFT=0` escape hatch lets the user opt out, but the underlying resolvability problem is something talkbox can fix itself. The e2e suite already does so with `export PATH="/usr/sbin:/sbin:$PATH"` (`test/e2e/deny-allow.bats:7`).

## Option A: Prepend `/usr/sbin:/sbin` to `PATH` inside `install_nft_deny` (Recommended)

Before invoking the `nft` pipeline, augment `PATH` (scoped to the `install_nft_deny` invocation / the pipeline subshell) with the standard sbin directories so `nft` and `nsenter` are resolvable. The augmentation is local — it only affects the `podman unshare nsenter … nft` pipeline, not the caller's environment or the container's shell.

**Pros:** minimal one-line change; matches the mechanism the e2e suite already validates; no change to `plan_nft_deny`'s token interface or its exact-token unit tests (`nft` stays a bare name); transparent to the user.
**Cons:** relies on `PATH` inheritance through `podman unshare` → `nsenter` → `nft` (valid, but implicit); hardcodes the `/usr/sbin:/sbin` convention (correct for all mainstream distros).
**Robustness note:** if `nft` is genuinely absent (not installed), the pipeline still fails and Phase 14a's fail-hard path takes over — so the escape hatch remains meaningful for the "not installed at all" case, just not the "installed but off PATH" case.

## Option B: Resolve `nft` to an absolute path and thread it into `plan_nft_deny`

Add a resolver that locates `nft` (check `command -v nft`, then `/usr/sbin/nft`, then `/sbin/nft`) and passes the resolved absolute path as the `nft` token in `plan_nft_deny`'s output. The token becomes `/usr/sbin/nft -f -` instead of `nft -f -`.

**Pros:** fully explicit; doesn't depend on `PATH` inheritance; works even from a sanitized `env -i` invocation.
**Cons:** changes the `plan_nft_deny` token contract — the existing unit test asserting exact tokens `podman unshare nsenter -t 12345 -n nft -f -` must be updated, and the resolver becomes part of the planner's responsibility (mixing resolution with planning); `nsenter`/`podman`/`unshare` are still resolved via `PATH`, so it only partially removes the PATH dependency.

## Option C: Detect missing `nft` at startup and emit a diagnostic, no auto-fix

At `install_nft_deny` entry, check `command -v nft`; if missing, print a `talkbox:` hint pointing the user at `/usr/sbin` and then proceed to the normal (fail-hard / lax) path.

**Pros:** improves diagnosability without changing resolution behaviour.
**Cons:** does not actually fix the problem — the user still has to act; strictly dominated by Option A, which fixes it silently.

## Selected

Option A — prepend `/usr/sbin:/sbin` to `PATH` inside `install_nft_deny` (scoped to the pipeline). Confirmed by user.
