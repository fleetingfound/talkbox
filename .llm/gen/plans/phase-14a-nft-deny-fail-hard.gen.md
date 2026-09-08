# Phase 14a: `install_nft_deny` fails hard when the deny set cannot be enforced

#flow/redgreen #model/default

## Summary

Reverses the previously-recorded "warn and continue" semantics of `install_nft_deny` ([`lib/network.sh:135-152`](../../../lib/network.sh)): when the effective deny set is non-empty and the rules cannot be applied — whether because `podman inspect` fails to return the container PID or because the `nft` ruleset pipeline exits non-zero — the already-started container is stopped and a non-zero status propagates to the caller, aborting the container orchestration. The underlying `nft`/`nsenter` stderr is surfaced to the user. An env-var escape hatch `TALKBOX_STRICT_NFT=0` restores the previous warn-and-continue behaviour for hosts without `nft` on `PATH`. Also closes the test gap tracked in [`install-nft-deny-no-nonempty-test.gen.md`](../issues/install-nft-deny-no-nonempty-test.gen.md).

## Choice documents

This plan implements the four choices recorded in this conversation:

- [nft deny failure scope](../choices/nft-deny-failure-scope.gen.md) — both PID-lookup failure and `nft` pipeline failure abort.
- [nft deny error surfacing](../choices/nft-deny-error-surfacing.gen.md) — surface the underlying stderr.
- [nft deny failure escape hatch](../choices/nft-deny-failure-escape-hatch.gen.md) — `TALKBOX_STRICT_NFT=0` reverts to warn-and-continue; default is fail-hard.
- [nft deny failure container cleanup](../choices/nft-deny-failure-container-cleanup.gen.md) — stop (do not remove) the container before raising.
- [nft PATH resolution](../choices/nft-path-resolution.gen.md) — prepend `/usr/sbin:/sbin` to `PATH` inside `install_nft_deny` so `nft` is resolvable when installed but off the non-root `PATH`.

The reversal is recorded in [ip-deny-allow-enforcement.gen.md](../choices/ip-deny-allow-enforcement.gen.md) "Selected" section.

## Aspects of the specification implemented

- `SPEC.md` "network" / deny list contract: deny entries "are blocked" — now enforced unconditionally by default rather than warn-and-continue, restoring the unqualified contract noted in the review.
- The `offbox` no-op path is unchanged (deny/allow options do not affect `offbox`).

## Aspects deferred

- No change to `nft_deny_ruleset` ruleset text, `plan_nft_deny` token layout, or `deny_allow_args` set computation.
- No IPv6 CIDR carving changes.
- No change to the `offbox` executor (it does not call `install_nft_deny`).
- A `--strict` CLI flag is not introduced; the escape hatch is env-var only.

## External-facing functionality

- `onbox`/`netbox` (and the netbox `recontain`/`rebuild` verbs) started with a non-empty effective deny set will now **abort** with a `talkbox:` error on stderr (accompanied by the underlying `nft`/`nsenter` error) when the deny rules cannot be applied, instead of starting an interactive session with the deny list unenforced. The already-started container is stopped before the error is raised.
- Setting `TALKBOX_STRICT_NFT=0` in the environment restores the prior behaviour: a `talkbox: warning:` is emitted on stderr and the container start proceeds with the deny list unenforced. This now matters only when `nft` is genuinely not installed (not merely off `PATH`), since PATH augmentation resolves the common case transparently.
- The empty-deny-set path is unchanged (no `podman`/`nft` invocation, returns 0).

## Files to be created

None.

## Files to be modified

- [`lib/network.sh`](../../../lib/network.sh) — `install_nft_deny`:
  - Prepend `/usr/sbin:/sbin` to `PATH` (scoped to the function / the pipeline subshell) before invoking the `nft` pipeline, so `nft` and `nsenter` are resolvable when installed at their standard locations but off the non-root `PATH` (per [nft PATH resolution](../choices/nft-path-resolution.gen.md)). The augmentation is local — it only affects the `podman unshare nsenter … nft` pipeline, not the caller's environment.
  - On the PID-lookup failure path (currently `:142-145`): when strict (default), surface a `talkbox:` error and return non-zero; when `TALKBOX_STRICT_NFT=0`, keep the current warn-and-return-0 behaviour.
  - On the `nft` pipeline failure path (currently `:148-150`): remove the `>/dev/null 2>&1` stderr suppression so the underlying `nft`/`nsenter` error reaches the user; when strict (default), stop the container and return non-zero after surfacing a `talkbox:` error; when `TALKBOX_STRICT_NFT=0`, keep the current warn-and-return-0 behaviour (stderr may still be surfaced for diagnosability — see note below).
  - The success path (pipeline exits 0) is unchanged: no warning, return 0.
  - A small helper or local predicate reads `TALKBOX_STRICT_NFT` and determines strict-vs-lax behaviour. The default (unset or any truthy value) is fail-hard; `0` / empty-falsy selects lax.
- [`lib/containers.sh`](../../../lib/containers.sh) — the four call sites (`run_onbox` `:223`, `run_netbox` `:688`, `run_netbox_recontain` `:741`, `run_netbox_rebuild` `:771`):
  - Propagate `install_nft_deny`'s non-zero return: stop the container (using `STOP_GRACE_SECONDS`) if not already stopped by the installer, then `die` with a `talkbox:` message and exit code 1. This mirrors the existing fatal-start-failure pattern used for `wait_for_entrypoint` (`:191`).
  - To avoid duplicating the stop-and-die logic across four sites, introduce a thin wrapper (e.g. `install_nft_deny_or_die <ctr> <deny> <allow>`) in `lib/containers.sh` that calls `install_nft_deny`, and on non-zero return stops the container and `die`s. The four call sites invoke the wrapper instead of `install_nft_deny` directly. (The wrapper lives in `containers.sh` because `STOP_GRACE_SECONDS` is defined there and container lifecycle is a `containers.sh` responsibility; `network.sh` sources only `common.sh`.)

  Implementation note for the redgreen subagent: decide at implementation time whether the container stop happens inside `install_nft_deny` or in the `containers.sh` wrapper — either is acceptable provided the container is stopped exactly once before the error is raised, and the unit tests for `install_nft_deny` (which use a fake `podman` on `PATH`) can observe the stop. The recommended split: `install_nft_deny` returns non-zero and surfaces stderr but does **not** stop (keeping it unit-testable without a real container); the `containers.sh` wrapper performs the stop and `die`.

## Relevant files to read during implementation

- [`lib/network.sh`](../../../lib/network.sh) (`:126-152`) — `plan_nft_deny`, `install_nft_deny`.
- [`lib/containers.sh`](../../../lib/containers.sh) (`:9` `STOP_GRACE_SECONDS`; `:185-191` `wait_for_entrypoint`/`die` pattern; `:221-235` `run_onbox`; `:686-700` `run_netbox`; `:740-742` `run_netbox_recontain`; `:770-772` `run_netbox_rebuild`).
- [`lib/common.sh`](../../../lib/common.sh) (`:3-7` `die`).
- [`test/unit/network.bats`](../../../test/unit/network.bats) (`:295-311` existing empty-deny-set `install_nft_deny` test — the shim pattern to reuse).
- [`test/e2e/deny-allow.bats`](../../../test/e2e/deny-allow.bats) (passing-path e2e tests; `require_nft_and_internet` / `require_nft_ipv6` skip guards).
- [`test/e2e/helpers.bash`](../../../test/e2e/helpers.bash) (e2e harness; `mk_talkbox` empties `defaults/deny.ip`/`allow.ip`).
- [`.llm/gen/tests/phase-12c-ip-deny-allow-enforcement.gen.md`](../tests/phase-12c-ip-deny-allow-enforcement.gen.md) (the planned-but-unimplemented "warns and returns success" test — now superseded by the fail-hard tests below).
- [`.llm/gen/reviews/nftables-deny-install-warning.gen.md`](../reviews/nftables-deny-install-warning.gen.md) (rationale for the reversal).

## Key internal interfaces

- `install_nft_deny <ctr> <deny-nameref> <allow-nameref>` — contract change: returns non-zero (and surfaces underlying stderr) when the deny set is non-empty and either the PID lookup or the `nft` pipeline fails, **unless** `TALKBOX_STRICT_NFT` selects lax mode, in which case it returns 0 after emitting a `talkbox: warning:` (the prior behaviour). Empty deny set: unchanged (returns 0, no podman call). The function does not stop the container; that is the caller's responsibility.
- `install_nft_deny_or_die <ctr> <deny-nameref> <allow-nameref>` (new, `lib/containers.sh`) — calls `install_nft_deny`; on non-zero return, runs `podman stop -t "$STOP_GRACE_SECONDS" "$ctr"` and `die "cannot apply nftables deny/allow rules in container $ctr; deny list left unenforced" 1`. Replaces the four direct `install_nft_deny` call sites in `run_onbox`/`run_netbox`/`run_netbox_recontain`/`run_netbox_rebuild`.
- `TALKBOX_STRICT_NFT` environment variable — `0` selects lax (warn-and-continue); unset or any other value selects strict (fail-hard, the default). Read inside `install_nft_deny`. With PATH augmentation in place, this escape hatch now only matters when `nft` is genuinely not installed on the host.

## Tests

This phase requires tests. The existing test suite has no test that pins the non-empty-deny install path (the gap tracked in the issue), so no existing test is inconsistent with the new fail-hard behaviour; the redgreen first subagent adds failing tests, the second implements.

### Unit tests — `test/unit/network.bats`

Add tests using the existing fake-`podman`-on-`PATH` shim pattern (see `:295-311`), covering:

- `install_nft_deny` with a non-empty deny set and a `podman inspect` that exits non-zero → asserts a `talkbox:` error is emitted on stderr, the underlying `podman inspect` stderr is surfaced, and the function returns non-zero. (PID-lookup failure path, strict mode.)
- `install_nft_deny` with a non-empty deny set, a `podman inspect` that succeeds (returns a PID), and an `nft` pipeline that exits non-zero → asserts a `talkbox:` error on stderr, the underlying `nft`/`nsenter` stderr is surfaced (not suppressed), and the function returns non-zero. (nft pipeline failure path, strict mode.)
- `install_nft_deny` with a non-empty deny set and a pipeline that succeeds → asserts no `talkbox:` warning/error is emitted and the function returns 0. (Success path.) To exercise the PATH-augmentation behaviour, this test should place a fake `nft` (and the fake `podman` shim) under `/usr/sbin`-equivalent directories on `PATH` *after* the sbin entries, and assert the invocation still resolves — or more simply, assert that a fake `nft` placed only in a sbin-style directory is found by the augmented `PATH`. The exact mechanism is left to the implementing subagent, but the assertion must cover "nft not on the original PATH but present in a sbin directory is resolved".
- `install_nft_deny` with `TALKBOX_STRICT_NFT=0` and a `podman inspect` that exits non-zero → asserts the prior warn-and-return-0 behaviour (lax PID-lookup path).
- `install_nft_deny` with `TALKBOX_STRICT_NFT=0` and an `nft` pipeline that exits non-zero → asserts the prior warn-and-return-0 behaviour (lax nft-failure path).
- The existing empty-deny-set test (`:295-311`) continues to pass unchanged (empty set is a no-op regardless of strict mode).

The fake-`podman` shim must be parameterisable (exit code of `inspect`, exit code of the `unshare`/`nsenter`/`nft` sub-invocation) so both failure modes are exercisable without a real container or `nft` binary.

### End-to-end tests — `test/e2e/deny-allow.bats`

- Add an assertion to the existing passing-path `onbox`/`netbox` deny tests that the run emits **no** `talkbox: warning:` / `talkbox:` error line on stderr, so a silent-fallback regression is caught on hosts where `nft` is available (the gap noted in the issue's "Suggested coverage"). These tests remain gated behind `require_nft_and_internet` / `require_nft_ipv6`.
- Consider (optional, host-dependent) an e2e test that sets `TALKBOX_STRICT_NFT=0` and confirms a warn-and-continue path — only viable on hosts where `nft` can be made to fail deliberately (e.g. genuinely uninstalled), so this may be left as a unit-only assertion if no reliable e2e failure injection is available. The unit tests above are the primary coverage for the lax path.
- The e2e file's existing `export PATH="/usr/sbin:/sbin:$PATH"` in `setup()` (`test/e2e/deny-allow.bats:7`) becomes redundant once talkbox augments `PATH` itself, but it should be left in place — it is harmless and keeps the tests robust if the implementation detail changes.

### Test consistency

The previously-planned (never-implemented) unit test "`install_nft_deny` warns and returns success when the rules cannot be applied" described in [`.llm/gen/tests/phase-12c-ip-deny-allow-enforcement.gen.md`](../tests/phase-12c-ip-deny-allow-enforcement.gen.md) is superseded: the strict-mode tests now assert fail-hard, and the lax-mode tests (`TALKBOX_STRICT_NFT=0`) assert the warn-and-return-0 behaviour. Add a note to that test document recording the supersession.

## Issue resolution

On completion, mark [`install-nft-deny-no-nonempty-test.gen.md`](../issues/install-nft-deny-no-nonempty-test.gen.md) complete in [`.llm/gen/issues/INDEX.gen.md`](../issues/INDEX.gen.md) (change `- [ ]` to `- [x]`): the non-empty deny install path is now exercised by unit tests for all three branches (PID-lookup failure, nft-pipeline failure, success) plus the lax-mode variants, and the e2e passing-path tests assert the absence of the warning.
