# nft deny install failure — escape hatch

Switching the default to fail-hard will make `onbox`/`netbox` unusable on hosts where the deny set is non-empty (the stock `defaults/deny.ip` is non-empty) and `nft` is not on `PATH` (common on stock Debian/Ubuntu/Fedora non-root shells, since `nft` lives in `/usr/sbin`). The choice is whether to provide an opt-out that restores the previous warn-and-continue behaviour.

## Option A: No escape hatch — unconditional fail-hard

No env var or flag reverts to warn-and-continue. If the deny set is non-empty and `nft` fails, the start always aborts.

**Pros:** simplest; the security contract is unconditional, matching `SPEC.md:238` ("deny entries are blocked") without qualification.
**Cons:** out-of-the-box breakage on hosts without `nft` on `PATH`; users must fix their environment (symlink `/usr/sbin/nft` onto `PATH`) before `onbox`/`netbox` work with the stock deny list.

## Option B: Provide an env-var escape hatch (Recommended)

Introduce `TALKBOX_STRICT_NFT` (or similar): when set to a falsy value (e.g. `0`), revert to warn-and-continue; when unset or truthy, fail-hard. The default (unset) is fail-hard, so the security contract holds by default; users on hosts without `nft` can opt out.

**Pros:** preserves the security default while giving hosts without `nft` a documented escape; aligns with the review's "opt-in" recommendation (inverted: opt-out).
**Cons:** adds a configuration surface; the default fail-hard still breaks stock hosts until the user discovers the escape hatch.

## Option C: Default to warn-and-continue, opt-in strict via env var

Fail-hard only when `TALKBOX_STRICT=1` (or similar) is set; default remains warn-and-continue.

**Pros:** no out-of-the-box regression; security-conscious users opt in.
**Cons:** contradicts the user's explicit instruction ("an error should be raised instead of proceeding") which implies fail-hard as the default behaviour.

## Selected

Option B — fail-hard by default, with a `TALKBOX_STRICT_NFT` env-var escape hatch to revert to warn-and-continue. Confirmed by user.
