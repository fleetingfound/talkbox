# nft deny install failure — underlying error surfacing

Currently the `nft` pipeline is invoked as `nft_deny_ruleset "$2" "$3" | "${cmd[@]}" >/dev/null 2>&1`, suppressing all underlying `nft`/`nsenter`/`podman unshare` stderr. The user only sees the generic talkbox warning. When switching to fail-hard, the choice is whether to surface the underlying error.

## Option A: Surface the underlying stderr to the user (Recommended)

Remove the stderr suppression (keep stdout suppression, or capture and reprint stderr). The error message talkbox raises should include or be accompanied by the underlying `nft`/`nsenter` error so the user can diagnose whether the problem is "command not found" vs. a capability failure.

**Pros:** strictly more informative; lets the user distinguish a trivial `nft`-not-on-`PATH` misconfiguration from a host capability failure; the review explicitly recommends this.
**Cons:** slightly more implementation work (capture or pass-through stderr without leaking podman/nft noise on success).

## Option B: Keep stderr suppressed, emit only a talkbox error message

Replace the warning with a fatal talkbox error but do not surface the underlying error. The user must manually re-run the pipeline to diagnose.

**Pros:** minimal change; deterministic, curated error output.
**Cons:** poor diagnosability — the user knows it failed but not why; the review flags this as a footgun.

## Selected

Option A — surface the underlying stderr. Confirmed by user.
