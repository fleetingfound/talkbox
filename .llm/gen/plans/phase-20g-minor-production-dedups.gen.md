# Phase 20g: minor production deduplications

#flow/refactor #model/default

## scope

Resolves the minor production items of §9 of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md) that are not covered by the other Phase 20 plans.

- Implemented:
  - [lib/network.sh](../../../lib/network.sh): `install_nft_deny` emits each failure message twice per failure mode, differing only by the `warning:` prefix and the return value; a small fail-or-warn helper (pairing with the existing `nft_strict` predicate) carries one copy of each message with its strict/lax behaviour. Emitted stderr text, return codes and exit statuses are unchanged;
  - [lib/containers.sh](../../../lib/containers.sh): `install_nft_deny_or_die` and `run_setup_in_container` share the "on failure, stop the container and `die`" wrapper shape; a shared wrapper helper carries it, with the failure-specific message passed in;
  - [image/setup.sh](../../../image/setup.sh): the two git-remote branches differ only in the order of the `git remote add`/`set-url` fallback; a small `ensure_host_remote` helper (or equivalent single spelling) deduplicates them. Both fallback orders end in `|| true`, so the consolidation is behaviour-preserving.
- Deliberately **not** implemented (per the review's "intentional, do not fix" note): `warn()` in [lib/merge.sh](../../../lib/merge.sh) re-derives the `talkbox:` prefix because it must stay location-agnostic and sourceable inside containers; the fifteen one-line `run_*` delegates remain the documented dispatch surface.

No aspect of `SPEC.md` changes. External-facing behaviour is unchanged.

## files to be created

None. Modified: [lib/network.sh](../../../lib/network.sh), [lib/containers.sh](../../../lib/containers.sh), [image/setup.sh](../../../image/setup.sh). Update [MAP.gen.md](../../../MAP.gen.md) descriptions where they change.

## relevant files to be read

- [lib/network.sh](../../../lib/network.sh), [lib/containers.sh](../../../lib/containers.sh), [image/setup.sh](../../../image/setup.sh)
- [test/unit/network.bats](../../../test/unit/network.bats) (install_nft_deny behaviour-pinning tests), [test/e2e/git-identity.bats](../../../test/e2e/git-identity.bats) and [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats) (setup.sh coverage)

## key internal interfaces

- New fail-or-warn helper in [lib/network.sh](../../../lib/network.sh) used by `install_nft_deny`; `install_nft_deny`'s signature is unchanged.
- New stop-and-die wrapper helper in [lib/containers.sh](../../../lib/containers.sh) used by `install_nft_deny_or_die` and `run_setup_in_container`; both keep their signatures, messages and exit codes.
- New `ensure_host_remote` helper (or single consolidated spelling) in [image/setup.sh](../../../image/setup.sh).

## tests

Unit tests required for the network half: the existing `install_nft_deny` tests in [test/unit/network.bats](../../../test/unit/network.bats) pin the exact stderr messages and return values for the strict and lax modes and must keep passing unchanged; the wrapper shape in [lib/containers.sh](../../../lib/containers.sh) is pinned by the existing executor-ordering tests (stop-then-die placement relative to nft and setup.sh). The [image/setup.sh](../../../image/setup.sh) change is covered end-to-end by the existing git-identity and git-transport e2e suites. No existing tests are superseded or removed.
