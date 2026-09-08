# Phase 12b: IP deny/allow parsing, option threading and onbox/netbox pasta string

#flow/redgreen #model/default

## Aspects of SPEC.md implemented

Implements the parsing and option-threading aspects of the IP deny/allow feature from the `## network` section of `SPEC.md`:

- `defaults/deny.ip` and `defaults/allow.ip` files listing IP addresses and CIDR ranges (one per line), with blank lines and `#`-comment lines ignored (same conventions as `read.mounts`, `write.mounts`, `ports`).
- The repeatable arguments `--deny-ip` and `--allow-ip`.
- The union of `defaults/deny.ip` and `--deny-ip` forms the deny set; the union of `defaults/allow.ip` and `--allow-ip` forms the allow set.
- The effective deny set is the deny set minus the allow set, with loopback addresses (`127.0.0.0/8`, `::1`) and `169.254.1.1` always removed (always allowed), even when matched by `defaults/deny.ip`.
- These options affect only `onbox` and `netbox`; they do not affect `offbox`.

Also closes a pre-existing gap relative to `SPEC.md`: the `onbox` and `netbox` pasta network string must include `--dns-forward,169.254.1.1,--map-guest-addr,none` (the fixed DNS-forward address that the "always allow `169.254.1.1`" rule depends on).

### Aspects deferred

- Actual enforcement of the effective deny set via nftables rules in the container netns is deferred to [Phase 12c](phase-12c-ip-deny-allow-enforcement.gen.md). This phase produces the computed effective deny set and threads it through to the executors, but does not yet block traffic.

## External-facing functionality

- `onbox`/`netbox`/`offbox` accept the new repeatable `--deny-ip <addr>` and `--allow-ip <addr>` options (each takes an IP address or CIDR range).
- `defaults/deny.ip` and `defaults/allow.ip` are honoured when present (and may be absent or empty).
- Missing-value cases for `--deny-ip` / `--allow-ip` emit a `talkbox: <option> requires a value` message and exit 2, matching the established pattern for `--read` / `--write` / `--port`.
- The `onbox` and `netbox` container plans emit `--network=pasta:-T,<port>,...--dns-forward,169.254.1.1,--map-guest-addr,none` (with the `-T,<port>` tokens unchanged). The `offbox` pasta string is unchanged.

## Files to be created

None. All changes are to existing files.

## Files to be read during implementation

- [lib/network.sh](lib/network.sh) (renamed in Phase 12a) — `port_args` and the module bootstrap.
- [lib/options.sh](lib/options.sh) — argument parsing, `TALKBOX_PORT` etc.
- [lib/containers.sh](lib/containers.sh) — `plan_onbox`, `plan_netbox`, `plan_offbox` (pasta string construction), and the executor signatures (`run_onbox`, `run_netbox`, `run_offbox`, the recontain/rebuild planners).
- [talkbox.sh](talkbox.sh) — action functions that call `port_args` and pass arrays into the planners/executors.
- [test/unit/options.bats](test/unit/options.bats) and [test/unit/network.bats](test/unit/network.bats) (the latter from Phase 12a) — existing parsing tests to extend.

## Key internal interfaces to be modified

- `lib/options.sh`: add `TALKBOX_DENY_IP=()` and `TALKBOX_ALLOW_IP=()` arrays; parse `--deny-ip` / `--allow-ip` (repeatable, value required, `die` on missing value).
- `lib/network.sh`: add a deny/allow parsing function (mirroring `port_args`) that reads `defaults/deny.ip` and `defaults/allow.ip`, unions them with the CLI arrays, and computes the effective deny set (deny minus allow minus the always-allowed loopback/`169.254.1.1` entries), returning it as an array of IP/CIDR strings. The function is pure (no podman) so it is unit-testable by sourcing `lib/network.sh` alone.
- `lib/containers.sh`: `plan_onbox` and `plan_netbox` append `--dns-forward,169.254.1.1,--map-guest-addr,none` to the pasta network string (after any `-T,<port>` tokens). `plan_offbox` is unchanged.
- `talkbox.sh`: the `onbox_action` and `sandbox_action` functions call the new deny/allow parsing function and thread the resulting effective-deny-set array into `run_onbox` / `run_netbox` (and the netbox recontain/rebuild executors) alongside the existing `ports` array. `offbox` does not receive the deny set.
- The onbox/netbox executor and recontain/rebuild planner signatures gain a nameref parameter for the effective deny set (offbox paths receive an empty array).

## Tests

Requires tests, including:

- unit tests:
  - deny/allow parsing: file-only, CLI-only, union, dedup, blank/comment-line handling, absent/empty files.
  - effective-set computation: allow overrides deny; loopback (`127.0.0.0/8`, `::1`) and `169.254.1.1` always removed from the deny set even when present in `defaults/deny.ip`; CIDR containment (an allow entry narrower than a deny CIDR removes only the allowed range where supported, otherwise the allowed literal entry is removed).
  - options: `--deny-ip` / `--allow-ip` record repeatable values; missing-value cases emit the talkbox message and exit 2.
  - `plan_onbox` / `plan_netbox` emit `--dns-forward,169.254.1.1,--map-guest-addr,none` in the `--network=` token; `plan_offbox` does not.
- No end-to-end tests in this phase (enforcement behaviour is verified in Phase 12c).

## Verification

`make lint`, `make format`, `make test-unit`.
