# Plan: Phase 6b — Rename `parse_onbox_options` to `parse_talkbox_options`

#flow/unified #model/default

## Specification scope

No aspect of `SPEC.md` / `SPEC.gen.md` is altered and no implementation behaviour changes. This resolves the open issue [`parse_onbox_options` is misleadingly named](../issues/parse-onbox-options-misleading-name.gen.md). The function is container-agnostic (called for onbox, netbox and offbox) but carries the historical `onbox` name; the `ONBOX_*` option variables are similarly prefixed despite holding the parsed options for whichever container the dispatcher is acting on.

## To be implemented

A mechanical, behaviour-preserving rename across the implementation and unit tests:

- Rename the function `parse_onbox_options` → `parse_talkbox_options` in [lib/options.sh](../../../lib/options.sh) and at both call sites in [talkbox.sh](../../../talkbox.sh) (`onbox_action`, `sandbox_action`).
- Rename the option variables `ONBOX_COMMAND` / `ONBOX_INTERACTIVE` / `ONBOX_VERB` / `ONBOX_ALL` / `ONBOX_BRANCH` / `ONBOX_READ` / `ONBOX_WRITE` / `ONBOX_PORT` / `ONBOX_FRESH` / `ONBOX_INHERIT` → `TALKBOX_COMMAND` / `TALKBOX_INTERACTIVE` / `TALKBOX_VERB` / `TALKBOX_ALL` / `TALKBOX_BRANCH` / `TALKBOX_READ` / `TALKBOX_WRITE` / `TALKBOX_PORT` / `TALKBOX_FRESH` / `TALKBOX_INHERIT` in:
  - [lib/options.sh](../../../lib/options.sh) (definitions and assignments).
  - [talkbox.sh](../../../talkbox.sh) (reads in `onbox_action` and `sandbox_action`).
  - [lib/containers.sh](../../../lib/containers.sh) (reads of `ONBOX_FRESH` / `ONBOX_INHERIT` in `create_netbox`, `create_offbox`, `run_netbox_recontain`, `run_offbox_recontain`, `run_netbox_rebuild`, `run_offbox_rebuild`).
- Update [test/unit/options.bats](../../../test/unit/options.bats): the `setup()` block's variable declarations and every assertion that references `ONBOX_*` / `parse_onbox_options`.
- Update [MAP.gen.md](../../../MAP.gen.md) if the `lib/options.sh` description references the old names.

Note: the `ONBOX_CTR` variables in the e2e test files are unrelated local test fixtures (container-name variables, not parsed options) and should **not** be renamed.

## To be deferred

- Nothing.

## External-facing functionality

None — no user-facing behaviour changes. The rename is internal.

## Files to be created

- None.

## Files to read during implementation

- [lib/options.sh](../../../lib/options.sh) — function definition and all `ONBOX_*` assignments.
- [talkbox.sh](../../../talkbox.sh) — call sites and `ONBOX_*` reads.
- [lib/containers.sh](../../../lib/containers.sh) — `ONBOX_FRESH` / `ONBOX_INHERIT` reads.
- [test/unit/options.bats](../../../test/unit/options.bats) — declarations and assertions to rename.
- [MAP.gen.md](../../../MAP.gen.md) — `lib/options.sh` description.

## Key internal interfaces

- `parse_talkbox_options` (renamed from `parse_onbox_options`) — unchanged signature and behaviour.
- `TALKBOX_*` option variables (renamed from `ONBOX_*`) — unchanged meaning.

## Tests

This is a behaviour-preserving refactor where the test edits and implementation edits are inseparable (tests reference the renamed symbols by name), so the whole phase is implemented by a single agent.

- **Unit tests:** the existing [test/unit/options.bats](../../../test/unit/options.bats) cases (27 tests) must continue to pass after the rename; no new tests are required since the behaviour is unchanged. The `ShellCheck`/`shfmt` lint (`make lint` / `make format`) must remain clean.
- **End-to-end tests:** no e2e test changes are required; the full e2e suite should pass unchanged (it exercises the dispatcher through the external interface, which is unaffected by the internal rename).
