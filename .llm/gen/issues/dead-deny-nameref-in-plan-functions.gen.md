# Issue: dead `_deny` nameref parameter in plan functions

## summary

The plan functions `plan_recontain`, `plan_rebuild`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild` and `plan_offbox_rebuild` in [lib/containers.sh](../../../lib/containers.sh) each declare a `local -n _deny=...` nameref parameter that is never read inside the function. The deny set is enforced separately by the `run_*` executors via `install_nft_deny` after `podman start`. The parameter is threaded through the plan functions for no reason, and `# shellcheck disable=SC2034` pragmas mask the unused-variable warning.

## affected files

- [lib/containers.sh](../../../lib/containers.sh) — lines 115, 133, 463, 492, 521, 551 (`local -n _deny="$7"` / `local -n _deny="$9"` declarations inside the six plan functions).

Additionally, the netbox/offbox plan functions mis-initialise `local source="$9"` to the *deny array name* before correcting it to `source="${10}"` inside the `if (($# > 9))` block — a confusing artefact of the same vestigial parameter.

## evidence

`rg -n '_deny' lib/containers.sh` shows the declarations at lines 115, 133, 463, 492, 521, 551 with no subsequent reference to `_deny` within those function bodies. The only `_deny` reads are in the `run_*` executors (lines 231, 712, 765, 795) which call `install_nft_deny "$ctr" "${_deny[@]}"`.

## impact

Low. No correctness impact — the dead parameter is simply never used. It is a maintainability and readability hazard: readers infer the planners consume the deny set (the MAP.gen.md description even claims they do), and the shellcheck-disable pragmas hide the dead code from static analysis.

## suggested fix

Remove the `local -n _deny=...` declarations and the `if (($# > N)); then ... fi` deny-parameter blocks from all six plan functions, drop the deny argument from the call sites in `run_recontain`/`run_rebuild`/`run_netbox_recontain`/`run_offbox_recontain`/`run_netbox_rebuild`/`run_offbox_rebuild`, and remove the corresponding `# shellcheck disable=SC2034` pragmas. Fix `local source="$9"` in the netbox/offbox variants to read the source argument directly.
