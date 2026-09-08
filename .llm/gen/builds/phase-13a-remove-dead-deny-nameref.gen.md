# Phase 13a: Remove dead `_deny` nameref parameter from plan functions

Status: `SUCCESS`

This build implements [phase-13a-remove-dead-deny-nameref.gen.md](../plans/phase-13a-remove-dead-deny-nameref.gen.md): the vestigial `_deny` nameref parameter and its `if (($# > N))` conditional blocks are removed from the six plan functions, the associated `# shellcheck disable=SC2034` pragmas are dropped, the netbox/offbox plan functions now read `source` directly from its positional parameter instead of mis-initialising it to the deny array name, and the `run_*` executors no longer forward the deny array into the planners (they still receive and enforce it themselves via `install_nft_deny`). The dead-parameter issue [dead-deny-nameref-in-plan-functions.gen.md](../issues/dead-deny-nameref-in-plan-functions.gen.md) is resolved (marked complete in the issues index); no verdict or dispute documents apply and no new issues were found.

## Overview

- `lib/containers.sh` - removed the `local -n _deny=...` declarations and `if (($# > 6))` / `if (($# > 9))` deny-parameter blocks from `plan_recontain`, `plan_rebuild`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild` and `plan_offbox_rebuild`, together with the now-unnecessary `# shellcheck disable=SC2034` pragmas in the onbox pair; the netbox/offbox variants keep `local source="$9"` as the direct read of the source argument. The `plan_*` invocations inside `run_recontain`, `run_rebuild`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild` and `run_offbox_rebuild` drop the forwarded deny-array argument; the executors' signatures and their `install_nft_deny "$ctr" "$6" "$7"` calls are unchanged.
- `MAP.gen.md` - the `lib/containers.sh` description corrected to state that only the `run_*` executors receive and enforce the deny-set and allow-set arrays (the recontain/rebuild planners no longer consume them).
- `.llm/gen/issues/INDEX.gen.md` - the dead `_deny` nameref issue marked resolved by this phase.

## Verification

- `make lint` - clean.
- `make format` - no formatting changes.
- `make test-unit` - exit `0`; 242/242 tests passed (the deny-less plan-function test call sites, adapted in the preceding commit, pass against the refactored implementation).
- `make test-e2e` - exit `0`; 73/73 tests passed with 0 skipped, confirming the `run_*` executors' external behaviour is unchanged.
