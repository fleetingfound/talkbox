# nft deny install failure — failure scope

The user instruction states: when the deny set is non-empty and calling `nft` produces an error, an error should be raised instead of proceeding. `install_nft_deny` ([`lib/network.sh:135-152`](../../../lib/network.sh)) has two distinct failure precursors before the `nft` invocation is even reached, plus the `nft` pipeline failure itself. The scope of which conditions should abort the container start is a design choice.

## Option A: Only the `nft` pipeline failure aborts (Recommended)

`podman inspect` failing to return a PID is treated as a distinct, earlier condition (the container may not be running, or podman is misbehaving). Only the case where the PID was obtained and the `nft` ruleset pipeline exited non-zero aborts. This matches the literal user instruction ("calling `nft` produces an error").

**Pros:** matches the user's stated condition precisely; a PID-lookup failure already prevents any `nft` call from being attempted, so conflating it with "nft produced an error" is imprecise.
**Cons:** two different failure paths with different semantics; the PID-lookup failure still warn-and-continues, leaving a partial inconsistency.

## Option B: Both the PID-lookup failure and the `nft` pipeline failure abort

Any failure to apply the deny rules — whether because the PID could not be determined or because the `nft` pipeline failed — raises an error and aborts. Treats "deny list requested but not enforceable" uniformly.

**Pros:** consistent security posture: if you asked for a deny list and it could not be enforced, abort, regardless of which step failed.
**Cons:** broader than the user's literal instruction; a `podman inspect` transient failure now aborts a container that is otherwise up.

## Selected

Option B — both the PID-lookup failure and the `nft` pipeline failure abort the container start. Any failure to apply the deny rules raises an error. Confirmed by user.
