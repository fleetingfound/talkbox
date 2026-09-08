# Phase 12b: IP deny/allow parsing, option threading and onbox/netbox pasta string

Test document for [Phase 12b: IP deny/allow parsing, option threading and onbox/netbox pasta string](.llm/gen/plans/phase-12b-ip-deny-allow-parsing.gen.md), which adds `defaults/deny.ip` / `defaults/allow.ip` and repeatable `--deny-ip` / `--allow-ip` parsing, computes the effective deny set (deny minus allow minus the always-allowed loopback/`169.254.1.1` entries, with CIDR-containment carving), and appends `--dns-forward,169.254.1.1,--map-guest-addr,none` to the `onbox`/`netbox` pasta network strings (offbox unchanged). No e2e tests are added, per the plan ("No end-to-end tests in this phase (enforcement behaviour is verified in Phase 12c)"); the e2e suite remains green.

The new parsing contract exercised by these tests is `deny_allow_args <out-array> <deny-file> <allow-file> <deny-cli-array> <allow-cli-array>`, with the CLI arrays passed by name (nameref), mirroring `port_args` but returning plain IP/CIDR strings.

## New tests

`test/unit/network.bats` (14 tests) — the `deny_allow_args` parsing and effective-set function:

- deny/allow parsing: file entries in order; CLI entries unioned after file entries; CLI-only entries with absent files; blank/comment lines ignored and whitespace trimmed (deny file); absent/empty files yield no entries; duplicate entries deduplicated; allow-file blank/comment lines honoured.
- effective-set computation: an equal allow entry overrides a deny entry; allow entries from both the allow file and the CLI remove their deny counterparts; an allow entry matching nothing leaves the deny set unchanged; loopback (`127.0.0.0/8`, `::1`) and `169.254.1.1` are always removed even when present in `defaults/deny.ip`; an allow CIDR narrower than a deny CIDR removes only the allowed range (`10.0.0.0/8` minus `10.0.0.0/9` yields exactly `10.128.0.0/9`, and symmetrically via the CLI); a multi-entry deny set keeps its order while carving; the always-allowed `169.254.1.1` is carved out of a denied `169.254.0.0/16` (no output entry covers `169.254.1.1`, while the surrounding range remains covered).

`test/unit/options.bats` (5 tests) — `--deny-ip` / `--allow-ip`:

- repeatable values are recorded in `TALKBOX_DENY_IP` / `TALKBOX_ALLOW_IP`;
- a final `--deny-ip` / `--allow-ip` without a value exits 2 with the `talkbox: <option> requires a value` message, matching the `--read` / `--write` / `--port` pattern;
- a `--deny-ip` value is not treated as the command.

## Tests edited

- `test/unit/containers.bats` — "onbox plan uses rootless pasta networking without host-port forwarding": expected network token changed from `--network=pasta` to `--network=pasta:--dns-forward,169.254.1.1,--map-guest-addr,none`. The plan requires the new suffix: "`plan_onbox` and `plan_netbox` append `--dns-forward,169.254.1.1,--map-guest-addr,none` to the pasta network string (after any `-T,<port>` tokens)."
- `test/unit/containers.bats` — "onbox plan applies default mounts and pasta -T ports": expected network token changed to `--network=pasta:-T,8080,-T,9090,--dns-forward,169.254.1.1,--map-guest-addr,none`, per "The `onbox` and `netbox` container plans emit `--network=pasta:-T,<port>,...--dns-forward,169.254.1.1,--map-guest-addr,none` (with the `-T,<port>` tokens unchanged)."
- `test/unit/netbox-offbox.bats` — "netbox plan uses pasta networking without loopback restriction and drops caps" and "netbox plan forwards -T ports on pasta": same two token updates for `plan_netbox` (the `-i,lo`-absence and capability assertions are unchanged, and `plan_offbox`'s exact-string tests are untouched because the offbox pasta string is unchanged).
- `test/unit/containers.bats` and `test/unit/netbox-offbox.bats` — the `--init` / tmpfs / GPU / prompt-env recontain and rebuild planner tests (and their `setup()` blocks) now pass an empty `DENY` array, since "The onbox/netbox executor and recontain/rebuild planner signatures gain a nameref parameter for the effective deny set (offbox paths receive an empty array)". The onbox planners gain it as the final parameter (`plan_recontain out project interactive read write ports deny`); the netbox/offbox recontain/rebuild planners gain it between the ports and the root-source parameters.
- `test/unit/options.bats` — `setup()` now initialises `TALKBOX_DENY_IP=()` and `TALKBOX_ALLOW_IP=()` alongside the other recorded options.

## Tests removed

None. No existing test was fully inconsistent with the plan; the four pasta-string assertions and the recontain/rebuild planner call sites above were updated in place, and every other existing test (including all offbox plan tests, which assert the unchanged `pasta:-i,lo,-I,talkbox0` strings) remains valid both before and after implementation.
