# Phase 12a: Rename `lib/ports.sh` to `lib/network.sh`

Status: `SUCCESS`

This build implements [phase-12a-rename-ports-to-network.gen.md](../plans/phase-12a-rename-ports-to-network.gen.md): a behaviour-preserving structural refactor that renames the ports module to the broader `lib/network.sh`, preparing `lib/` for the IP deny/allow feature (parsing in [Phase 12b](../plans/phase-12b-ip-deny-allow-parsing.gen.md) and firewall-rule application in [Phase 12c](../plans/phase-12c-ip-deny-allow-enforcement.gen.md)). No external-facing behaviour changes.

## Overview

- `lib/network.sh` - `lib/ports.sh` renamed via `git mv`; contents identical (`# shellcheck shell=bash` header and `TALKBOX_ROOT` bootstrap preserved). The `port_args` function name and signature are unchanged.
- `talkbox.sh` - the `source "$TALKBOX_ROOT/lib/ports.sh"` line became `source "$TALKBOX_ROOT/lib/network.sh"`.
- `test/unit/ports.bats` - renamed via `git mv` to `test/unit/network.bats`.
- `test/unit/network.bats`, `test/unit/containers.bats`, `test/unit/netbox-offbox.bats`, `test/unit/lifecycle.bats` - every `load_lib ports.sh` call became `load_lib network.sh`.
- `MAP.gen.md` - the `lib/ports.sh` entry updated to `lib/network.sh`.

## Test edits

- `test/unit/ports.bats` renamed to `test/unit/network.bats` with all six `load_lib ports.sh` calls updated; `test/unit/containers.bats`, `test/unit/netbox-offbox.bats` and `test/unit/lifecycle.bats` each had their single `load_lib ports.sh` call updated. These are mechanical renames required by the plan: "`test/unit/ports.bats` is renamed to `test/unit/network.bats`; every `load_lib ports.sh` call (across `network.bats`, `containers.bats`, `netbox-offbox.bats`, `lifecycle.bats`) becomes `load_lib network.sh`." No test assertions were altered in meaning, and no tests were added or removed.

## Verification

- `make lint` - clean.
- `make format` - no formatting changes.
- `make test-unit` - exit `0`; 216/216 tests passed (including the 6 `network.bats` `port_args` cases).
- `make test-e2e` - exit `0`; 68/68 tests passed unchanged.
