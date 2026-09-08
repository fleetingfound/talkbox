# nftables deny/allow install failure — warning, test gap, and fail-hard consideration

## Summary

When running `netbox` (or `onbox`) with a non-empty effective deny set, talkbox installs an `nftables` ruleset inside the container's network namespace after `podman start`. If that install step fails, talkbox emits the warning

```
talkbox: warning: cannot apply nftables deny/allow rules in container <name>; deny list left unenforced
```

and continues starting the container. This document explains why the warning fires, why the test suite does not exercise it, and evaluates whether aborting on failure would be preferable.

## Where the warning comes from

The whole deny/allow enforcement pipeline lives in [`lib/network.sh`](../../../lib/network.sh):

- `deny_allow_args` (`:33-73`) builds the effective deny/allow sets from `defaults/deny.ip` / `defaults/allow.ip` plus `--deny-ip` / `--allow-ip`.
- `nft_deny_ruleset` (`:105-124`) emits the `nft` ruleset text (table `talkbox_deny` with `allowed` and `blocked` interval sets, an `@allowed accept` rule before the `@blocked drop` rule).
- `plan_nft_deny` (`:126-133`) appends the invocation tokens `podman unshare nsenter -t <PID> -n nft -f -` only when the deny set is non-empty.
- `install_nft_deny` (`:135-152`) is the executor:

```bash
install_nft_deny() {
	local ctr="$1"
	local -n _deny="$2"
	if ((${#_deny[@]} == 0)); then
		return 0
	fi
	local pid
	pid="$(podman inspect -f '{{.State.Pid}}' "$ctr" 2>/dev/null)" || {
		printf 'talkbox: warning: cannot determine the PID of container %s; deny/allow rules not applied\n' "$ctr" >&2
		return 0
	}
	local -a cmd=()
	plan_nft_deny cmd "$pid" "$2" "$3"
	if ! nft_deny_ruleset "$2" "$3" | "${cmd[@]}" >/dev/null 2>&1; then
		printf 'talkbox: warning: cannot apply nftables deny/allow rules in container %s; deny list left unenforced\n' "$ctr" >&2
	fi
	return 0
}
```

Callers are `run_onbox` (`lib/containers.sh:223`), `run_netbox` (`:688`), `run_netbox_recontain` (`:741`), and `run_netbox_rebuild` (`:771`). `run_offbox` does not call it — offbox deny handling is a documented no-op.

## Why the warning fires

The line-149 warning is emitted exactly when **all three** hold:

1. the effective deny set is non-empty (otherwise the function returns early at `:138-140`), and
2. `podman inspect` returned a PID successfully (otherwise the line-143 warning fires instead), and
3. the `nft` install pipeline exits non-zero.

Concrete root causes for (3), per the implementation and the design notes in [`ip-deny-allow-enforcement.gen.md`](../choices/ip-deny-allow-enforcement.gen.md):

- `nft` is not resolvable on `PATH`. On most distributions `nft` lives in `/usr/sbin`, which is **not** on a non-root user's `PATH`. The pipeline redirects stderr to `/dev/null`, so the user only sees the generic talkbox warning, not the underlying `command not found`.
- `nsenter` is missing.
- `podman unshare` cannot grant `CAP_NET_ADMIN` in the rootless network namespace (kernel/user-session configuration, or podman build without rootless support).
- The `nft` ruleset text is rejected by the kernel (e.g. older kernel without interval-set support, or a syntax the installed `nft` does not understand).

### A note on the "new git repo" premise

The warning is **not** conditioned on the project being a fresh or newly-initialised git repository. The deny set is sourced from the talkbox checkout's `defaults/deny.ip` (a non-empty stock list of IANA special-purpose / private ranges) and/or `--deny-ip` flags — never from the user's project repository. The git-repo concept only enters the picture indirectly through the e2e harness, which uses a throwaway temporary git repo as `<project>` and *empties* the copied `defaults/deny.ip` / `defaults/allow.ip` so behaviour is driven only by CLI flags (`test/e2e/helpers.bash:39-47`).

So running `netbox` in a brand-new git repo does not itself trigger this warning; what the user is observing is the `nft` install pipeline failing on their host (most likely cause: `nft` not on `PATH`) on a run that happened to use a fresh repo. The repo state is coincidental, not causal.

## Why the test suite does not capture it

There are two test layers and neither covers the failing-install path:

### Unit tests — `test/unit/network.bats`

The unit tests cover:

- the ruleset *text* emitted by `nft_deny_ruleset` for various deny/allow combinations (`:191-279`),
- that `plan_nft_deny` produces no invocation tokens when the deny set is empty (`:287`),
- that `install_nft_deny` with an empty deny set performs no `podman` invocation (`:295-311`).

There is **no unit test for the non-empty-deny install path** — neither the success path (rules applied, no warning) nor the failure path (pipeline exits non-zero, line-149 warning emitted, function returns 0). The planned test "`install_nft_deny` warns and returns success when the rules cannot be applied" is described in [`phase-12c-ip-deny-allow-enforcement.gen.md`](../tests/phase-12c-ip-deny-allow-enforcement.gen.md) but was never implemented. The gap is tracked in [install_nft_deny has no test for the non-empty deny install path or its warning](../issues/install-nft-deny-no-nonempty-test.gen.md).

### E2E tests — `test/e2e/deny-allow.bats`

The e2e tests do exercise the real install path (`onbox --deny-ip blocks a denied address`, `netbox --deny-ip blocks a denied address`, etc.), but:

- they are gated behind `require_nft_and_internet` / `require_nft_ipv6` and **skip** when `nft` or IPv6 or internet is unavailable (`:22-35`) — i.e. exactly the conditions that produce the warning are the conditions under which the tests silently skip; and
- none of the passing-path tests asserts the *absence* of the warning on stderr, so a regression that silently falls back to warn-and-continue would not be detected even on a host where `nft` is available.

The combination means: on hosts without `nft` on `PATH` the unit suite never exercises `install_nft_deny` with a non-empty deny set, and the e2e suite skips. The warn-and-continue behaviour is therefore entirely unverified.

## Is failing hard preferable?

The current behaviour — warn and continue with the deny list unenforced — is an explicit documented choice, recorded in [`ip-deny-allow-enforcement.gen.md`](../choices/ip-deny-allow-enforcement.gen.md:13,43):

> If the capability is unavailable, talkbox warns and continues (deny list not enforced) rather than aborting the container start.

### Arguments for the current warn-and-continue behaviour

- **Deny is a hardening layer, not the primary isolation boundary.** The container is already network-isolated by pasta's rootless netns; the deny list only narrows *which* destinations are reachable inside that netns. A failed deny install degrades hardening but does not by itself grant new access.
- **Environment fragility.** `nft` not being on `PATH` is a trivial misconfiguration that the user can fix without disrupting the rest of the workflow; aborting would make talkbox unusable on stock Debian/Ubuntu/Fedora installs until the user symlinks `/usr/sbin/nft` onto `PATH`.
- **Failures are often host-wide and persistent.** If `podman unshare` cannot acquire `CAP_NET_ADMIN`, every subsequent `netbox`/`onbox` invocation will fail identically; aborting turns a partial-degradation into a total outage of the onbox/netbox verbs.

### Arguments for failing hard

- **Silent degradation is a security footgun.** A user who has populated `defaults/deny.ip` with the expectation that those addresses are unreachable has no easy way to tell, post-start, that the rules were not applied — the warning goes to stderr at start time and is easy to miss in a busy terminal. `SPEC.md` (`:238`) states deny entries "are blocked" without qualification; warn-and-continue violates that contract in practice.
- **The user's stated expectation.** The user reports the warning as surprising and asks whether aborting would be preferable, which is consistent with the security-principle-of-least-surprise view: if you asked for a deny list and it could not be enforced, do not silently start the container with the list unenforced.
- **The current stderr-suppression makes diagnosis hard.** `>/dev/null 2>&1` swallows the real `nft` error; the user only sees the generic talkbox warning and has to manually re-run the pipeline to find out *why* it failed. Failing hard with the underlying error would be strictly more informative.

### Recommendation

A **middle path** is preferable to either extreme, and is the smallest change that resolves the footgun without the outage cost:

1. **Capture and surface the underlying `nft`/`nsenter` error** instead of suppressing it with `2>&1 >/dev/null`. The user can then see whether the problem is "command not found" (fixable by the user) vs. a capability failure (host configuration).
2. **Add an opt-in strict mode** (e.g. `TALKBOX_STRICT=1` or a `--strict` flag, or honour an existing strict-mode convention if one exists in the codebase) that turns the warning into a fatal error and aborts the start. This lets security-conscious users opt into fail-hard behaviour without breaking the out-of-the-box experience on hosts where `nft` is merely off `PATH`.
3. **Add the missing unit test** for the non-empty-deny failure path (see linked issue) so the behaviour — whatever it is — is pinned and regressions are caught.

Unconditionally aborting on install failure is **not recommended as a default**: it trades a partial, host-local hardening degradation for a total loss of the onbox/netbox verbs on every host where `nft` is not on `PATH`, which is common and trivially fixable by the user once the real error is visible. The strict-mode opt-in captures the security benefit for users who want it without imposing that cost.

## Related

- [install_nft_deny has no test for the non-empty deny install path or its warning](../issues/install-nft-deny-no-nonempty-test.gen.md)
- [netbox network isolation review](netbox-network-isolation.gen.md)
- [IP deny/allow enforcement mechanism — choices](../choices/ip-deny-allow-enforcement.gen.md)
