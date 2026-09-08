# Phase 14a: `install_nft_deny` fails hard when the deny set cannot be enforced

Status: `SUCCESS`

This build implements [phase-14a-nft-deny-fail-hard.gen.md](../plans/phase-14a-nft-deny-fail-hard.gen.md): `install_nft_deny` now fails hard by default when the effective deny set is non-empty and either the `podman inspect` PID lookup or the `nft` ruleset pipeline fails — surfacing the underlying stderr with a `talkbox:` error and returning non-zero — while `TALKBOX_STRICT_NFT=0` restores the prior warn-and-continue behaviour, and the pipeline's `PATH` is augmented with `/usr/sbin:/sbin` so `nft`/`nsenter` installed at their standard locations resolve when off the caller's `PATH`. The four `run_*` call sites in `lib/containers.sh` now go through a new `install_nft_deny_or_die` wrapper which stops the container (`STOP_GRACE_SECONDS`) and `die`s before the error propagates. The test-gap issue [install-nft-deny-no-nonempty-test.gen.md](../issues/install-nft-deny-no-nonempty-test.gen.md) is resolved (marked complete in the issues index); no verdict or dispute documents apply and no new issues were found.

## Overview

- `lib/network.sh` - added the `nft_strict` predicate (`TALKBOX_STRICT_NFT` unset or any value other than `0` selects fail-hard) and rewrote `install_nft_deny`: the strict PID-lookup failure path surfaces the underlying `podman inspect` stderr plus a `talkbox:` error and returns 1 (the lax path keeps the `2>/dev/null` suppression, the exact `talkbox: warning:` text and return 0); the `nft` pipeline now runs in a subshell with `/usr/sbin:/sbin` prepended to `PATH`, its stderr is no longer suppressed, and on failure the strict path emits a `talkbox:` error and returns 1 while the lax path keeps the exact `talkbox: warning:` text and returns 0. The empty-deny-set early return and the `plan_nft_deny` token layout are unchanged.
- `lib/containers.sh` - added the `install_nft_deny_or_die` wrapper (calls `install_nft_deny`; on non-zero return runs `podman stop -t "$STOP_GRACE_SECONDS" "$ctr"` and `die "cannot apply nftables deny/allow rules in container $ctr; deny list left unenforced" 1`) and replaced the four direct `install_nft_deny` call sites in `run_onbox`, `run_netbox`, `run_netbox_recontain` and `run_netbox_rebuild`.
- `MAP.gen.md` - updated the `lib/network.sh` and `lib/containers.sh` descriptions to reflect the fail-hard default, the lax escape hatch, the `PATH` augmentation and the stop-and-die wrapper.
- `.llm/gen/issues/INDEX.gen.md` - the non-empty-deny test-gap issue marked resolved by this phase.

## Verification

- `make lint` - clean.
- `make format` - no formatting changes.
- `make test-unit` - exit `0`; 247/247 tests passed, including the five new `install_nft_deny` tests (strict PID-lookup failure, strict `nft`-pipeline failure, success with sbin-`PATH` resolution, and both `TALKBOX_STRICT_NFT=0` lax guards) added by the red tests in `test/unit/network.bats`.
- `make test-e2e` - exit `0`; 73/73 tests passed with 0 skipped, including the deny/allow enforcement tests which now assert no `talkbox:` line on their passing-path runs.
- Manual smoke check (not a committed test): with a `podman` shim failing `unshare`, a strict `onbox --deny-ip` run aborted with exit 1, surfaced the shim's `nft` stderr and both `talkbox:` error lines, left the container stopped (never ran the exec), while `TALKBOX_STRICT_NFT=0` warned and completed the run with exit 0.
