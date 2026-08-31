# Phase 6b: Rename `parse_onbox_options` to `parse_talkbox_options`

Status: `SUCCESS`

This build implements [phase-6b-rename-parse-talkbox-options.gen.md](../plans/phase-6b-rename-parse-talkbox-options.gen.md), which resolves the issue [parse-onbox-options-misleading-name.gen.md](../issues/parse-onbox-options-misleading-name.gen.md): the container-agnostic option parser and its option variables carried the historical `onbox` name and were mechanically renamed to `parse_talkbox_options` / `TALKBOX_*`, with no behaviour change.

## Overview

- `lib/options.sh` - `parse_onbox_options()` renamed to `parse_talkbox_options()`; all ten option variables (`COMMAND` / `INTERACTIVE` / `VERB` / `ALL` / `BRANCH` / `READ` / `WRITE` / `PORT` / `FRESH` / `INHERIT`) renamed from `ONBOX_*` to `TALKBOX_*` (definitions and assignments). Signature and behaviour unchanged.
- `talkbox.sh` - both call sites (`onbox_action`, `sandbox_action`) call `parse_talkbox_options`; all reads of the option variables updated to `TALKBOX_*`.
- `lib/containers.sh` - reads of `ONBOX_FRESH` / `ONBOX_INHERIT` in `create_netbox`, `create_offbox`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild` renamed to `TALKBOX_FRESH` / `TALKBOX_INHERIT`.
- `test/unit/options.bats` - the `setup()` block's variable declarations and every assertion referencing `ONBOX_*` / `parse_onbox_options` renamed to `TALKBOX_*` / `parse_talkbox_options`.

## Test edits

- `test/unit/options.bats` - every test and the `setup()` block reference the renamed symbols by name; the plan requires this update: "Update [test/unit/options.bats](../../../test/unit/options.bats): the `setup()` block's variable declarations and every assertion that references `ONBOX_*` / `parse_onbox_options`." This is a behaviour-preserving rename of test references, not a change to test expectations; the plan states "the test edits and implementation edits are inseparable (tests reference the renamed symbols by name)". No test assertions were altered in meaning, and no tests were added or removed.

## Verification

- `make test-unit` - exit `0`; 162/162 tests passed (including the 25 `options.bats` cases).
- `make test-e2e` - exit `0`; 57/57 tests passed unchanged.
- `make lint` clean; `shfmt` reports no formatting changes on the edited scripts.
