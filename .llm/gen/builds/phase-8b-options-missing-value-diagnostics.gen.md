# Phase 8b: Options requiring a value emit talkbox messages instead of raw bash errors

Status: `SUCCESS`

This build implements [phase-8b-options-missing-value-diagnostics.gen.md](../plans/phase-8b-options-missing-value-diagnostics.gen.md), making `--read`, `--write`, `--port` and `--inherit` emit `talkbox: <option> requires a value` to stderr and exit 2 when supplied as the final argument with no following value, resolving [options-missing-value-unbound-variable.gen.md](../issues/options-missing-value-unbound-variable.gen.md).

## Overview

- `lib/options.sh` - in each of the four value-consuming cases (`--read`, `--write`, `--port`, `--inherit`), the post-`shift` access to `$1` is now guarded by an argument-count check (`[[ $# -gt 0 ]] || die "<option> requires a value" 2`), so `parse_talkbox_options` reports the usage error via the existing `die` helper (producing the `talkbox:` prefix and exit code 2) instead of aborting under `set -u` with a raw `$1: unbound variable` diagnostic.

## Verification

- `make test-unit` - exit `0`; 178/178 tests passed, including the four new tests asserting exit status 2 and the `talkbox: <option> requires a value` message.
- `make test-e2e` - exit `0`; 60/60 tests passed.
- `make lint` - no findings; `shfmt` reports no formatting changes.
