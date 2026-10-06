# Tests: Phase 20g minor production deduplications

Pinning-test pass for [phase-20g-minor-production-dedups](../plans/phase-20g-minor-production-dedups.gen.md), which plans three behaviour-preserving production deduplications — a fail-or-warn helper for the doubled failure messages in `install_nft_deny` (lib/network.sh), a shared stop-then-die wrapper for `install_nft_deny_or_die`/`run_setup_in_container` (lib/containers.sh), and a consolidated `ensure_host_remote` spelling for the two git-remote branches of image/setup.sh — with all stderr text, return codes and exit statuses unchanged. These tests pin the exact messages, return values and orderings those helpers must preserve; no core files were modified and every new and surviving test passes against the current implementation.

## New tests

### test/unit/network.bats

Three tests completing the exact-message/return-value pinning of `install_nft_deny`'s strict and lax modes (the plan's network half). The existing tests already pinned the two lax-mode warning messages with return 0 and the strict success path; these add the missing halves:

1. `install_nft_deny in strict mode emits the exact PID-lookup failure message and returns 1` — with `podman inspect` failing, pins the exact stderr line `talkbox: cannot determine the PID of container talkbox-proj.onbox; deny/allow rules not applied` (no `warning:` prefix), exit status exactly 1, and the surfaced underlying podman stderr.
2. `install_nft_deny in strict mode emits the exact nft-pipeline failure message and returns 1` — with the `podman unshare … nft` pipeline failing, pins the exact stderr line `talkbox: failed to apply nftables deny/allow rules in container talkbox-proj.onbox; deny list left unenforced`, exit status exactly 1, and the surfaced underlying nft stderr.
3. `install_nft_deny with TALKBOX_STRICT_NFT=0 applies the rules and emits no warning when the nft pipeline succeeds` — the lax success path emits nothing on stderr and returns 0, pinning that the planned fail-or-warn helper only speaks on failure.

### test/unit/containers.bats

Two tests pinning the stop-then-die wrapper shape of lib/containers.sh through the onbox executor, over the logging podman shim:

4. `run_onbox stops the container and dies with the exact nft error when the nft deny step fails` — with the nft pipeline failing, pins the exact die message `talkbox: cannot apply nftables deny/allow rules in container talkbox-proj.onbox; deny list left unenforced`, exit status exactly 1, and the stop placed after the nft invocation (the `install_nft_deny_or_die` wrapper half; only the setup.sh failure half was pinned before).
5. `run_onbox stops the container and dies with the exact setup error when the setup.sh exec fails` — with `podman exec … setup.sh` failing, pins the exact die message `talkbox: cannot run setup.sh in container talkbox-proj.onbox; setup failed`, exit status exactly 1, and the ordering nft → setup.sh → stop (the `run_setup_in_container` wrapper half; the existing setup-failure test pinned only stop-plus-error without the exact message or placement).

The image/setup.sh half needs no new tests: per the plan it is covered end-to-end by the existing git-identity and git-transport suites (host-remote wiring of fresh and existing gitdir volumes), which pass unchanged.

## Tests edited

None. The plan requires the existing `install_nft_deny` tests (test/unit/network.bats) and the executor-ordering tests (test/unit/containers.bats) to keep passing unchanged, and states no existing tests are superseded; all of them pass against the current implementation.

## Tests removed

None. The plan states "No existing tests are superseded or removed", and no tested internal interface disappears: `install_nft_deny` keeps its signature and emitted messages, both containers.sh wrappers keep their signatures, messages and exit codes, and the fifteen one-line `run_*` delegates remain the documented dispatch surface (their non-refactor is deliberate per the plan).

## Verification

Against the unmodified implementation: `make test-unit` 303/303 (298 existing + 5 new), `make test-e2e` 76/76, `shellcheck` and `shfmt -d` clean on both modified files.
