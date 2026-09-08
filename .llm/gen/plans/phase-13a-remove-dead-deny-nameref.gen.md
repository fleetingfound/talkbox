# Phase 13a: Remove dead `_deny` nameref parameter from plan functions

#flow/refactor #model/default

## aspect of the specification

No spec aspect is implemented or deferred. This is a maintainability refactor that removes vestigial dead code identified in [Dead `_deny` nameref parameter in plan functions](../issues/dead-deny-nameref-in-plan-functions.gen.md). Behaviour is preserved exactly.

## external-facing functionality

None — no externally observable behaviour changes. The deny set continues to be enforced by the `run_*` executors via `install_nft_deny` after `podman start`, exactly as before.

## files to be created

None.

## files to be modified

- [lib/containers.sh](../../../lib/containers.sh) — the six plan functions `plan_recontain`, `plan_rebuild`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild`, `plan_offbox_rebuild`:
  - Remove the `local -n _deny=...` declarations and the surrounding `if (($# > N)); then ... fi` deny-parameter blocks.
  - Remove the associated `# shellcheck disable=SC2034` pragmas that mask the unused-variable warning.
  - In the netbox/offbox variants, fix the `source` argument to be read directly from its positional parameter (no longer mis-initialised to the deny array name and then corrected in the conditional block).
  - At the call sites within `run_recontain`, `run_rebuild`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild`, drop the deny-array argument from the `plan_*` invocations (the executors still receive and use `_deny` themselves for `install_nft_deny` — only the forwarding into the plan functions is removed).
- [MAP.gen.md](../../../MAP.gen.md) — update the [lib/containers.sh](../../../lib/containers.sh) description, which currently (incorrectly) claims the recontain/rebuild planners consume the deny set; correct it to state that only the `run_*` executors receive and enforce the deny set.

## relevant files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — the six plan functions and their `run_*` call sites.
- [test/unit/containers.bats](../../../test/unit/containers.bats) — passes `DENY` as a trailing positional arg to the onbox `plan_recontain`/`plan_rebuild` test call sites.
- [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) — passes `DENY` as a positional arg before `base` in the netbox/offbox plan function test call sites.
- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) — the lifecycle plan-function tests (some already omit the deny arg; confirm consistency).

## key internal interfaces

- The six plan functions lose their trailing deny-array parameter. Their positional parameter lists shrink by one (the deny nameref). The netbox/offbox variants' `source` parameter shifts to the position previously occupied by the deny parameter.
- The `run_*` executor signatures are unchanged by this phase (they still receive `_deny` and pass it to `install_nft_deny`); only the forwarding of the deny array from the executors into the plan functions is removed.

## tests

Requires existing tests to be edited (behaviour-preserving).

- **Unit tests** (`test/unit/containers.bats`, `test/unit/netbox-offbox.bats`): remove the `DENY` positional argument from every `plan_recontain` / `plan_rebuild` / `plan_netbox_recontain` / `plan_offbox_recontain` / `plan_netbox_rebuild` / `plan_offbox_rebuild` invocation so the test call sites match the cleaned signatures. These edited tests must pass against the existing (pre-refactor) implementation, because the existing conditional blocks already tolerate an absent deny argument — confirming the refactor is behaviour-preserving.
- No new tests are required. No end-to-end tests are affected (the e2e suite exercises the `run_*` executors, whose external behaviour is unchanged).
