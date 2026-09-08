# Phase 12a: Rename `lib/ports.sh` to `lib/network.sh`

#flow/unified #model/default

## Aspects of SPEC.md implemented

None directly. This is a behaviour-preserving structural refactor that prepares `lib/` for the IP deny/allow feature ([IP deny/allow module structure](../choices/ip-deny-allow-module.gen.md)) by renaming the ports module to the broader `lib/network.sh`, into which deny/allow parsing and firewall-rule application will be added in [Phase 12b](phase-12b-ip-deny-allow-parsing.gen.md) and [Phase 12c](phase-12c-ip-deny-allow-enforcement.gen.md).

No aspects of `SPEC.md` or `SPEC.gen.md` are deferred by this phase; it introduces no external-facing change.

## External-facing functionality

None. The `onbox`, `netbox` and `offbox` commands behave exactly as before.

## Files to be created

- `lib/network.sh` — the renamed module (contents identical to the current `lib/ports.sh`, header `# shellcheck shell=bash` and `TALKBOX_ROOT` bootstrap preserved).

## Files to be read during implementation

- [lib/ports.sh](lib/ports.sh) — the module being renamed.
- [talkbox.sh](talkbox.sh) — sources `lib/ports.sh` and calls `port_args`.
- [test/unit/helpers.bash](test/unit/helpers.bash) — defines `load_lib`, used by unit tests.
- [test/unit/ports.bats](test/unit/ports.bats), [test/unit/containers.bats](test/unit/containers.bats), [test/unit/netbox-offbox.bats](test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](test/unit/lifecycle.bats) — reference `lib/ports.sh` / `port_args`.

## Key internal interfaces to be modified

- `talkbox.sh`: the `source "$TALKBOX_ROOT/lib/ports.sh"` line becomes `source "$TALKBOX_ROOT/lib/network.sh"`.
- `test/unit/ports.bats` is renamed to `test/unit/network.bats`; every `load_lib ports.sh` call (across `network.bats`, `containers.bats`, `netbox-offbox.bats`, `lifecycle.bats`) becomes `load_lib network.sh`.
- `MAP.gen.md`: the entry for `lib/ports.sh` is updated to `lib/network.sh`.
- The `port_args` function name and signature are unchanged.

## Tests

This phase requires tests to be updated (mechanically, via the rename) and must pass against the existing implementation:

- unit tests: the renamed `test/unit/network.bats` and the three other unit suites that `load_lib ports.sh` must continue to pass unchanged.
- No end-to-end tests are affected.

## Verification

`make lint`, `make format`, `make test-unit`.
