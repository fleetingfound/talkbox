# Issue: `parse_onbox_options` is misleadingly named

## Affected files

- [lib/options.sh](../../../lib/options.sh) — defines `parse_onbox_options` and the `ONBOX_*` option variables
- [talkbox.sh](../../../talkbox.sh) — calls `parse_onbox_options` for all three containers (onbox, netbox, offbox)
- [lib/containers.sh](../../../lib/containers.sh) — reads `ONBOX_FRESH` / `ONBOX_INHERIT` in the netbox/offbox executors
- [test/unit/options.bats](../../../test/unit/options.bats) — references `parse_onbox_options` and the `ONBOX_*` variables throughout

## Description

[lib/options.sh](../../../lib/options.sh) defines `parse_onbox_options` and uses `ONBOX_*` variable names for the parsed options of all three containers. The dispatcher in [talkbox.sh](../../../talkbox.sh) calls `parse_onbox_options` for onbox, netbox and offbox alike — the function is container-agnostic. The name is historical (onbox was the first container implemented).

The `ONBOX_*` prefix on the option variables is similarly misleading: it implies the variables are scoped to the onbox container, when in fact they hold the parsed options for whichever container the dispatcher is acting on.

## Suggested fix

Rename `parse_onbox_options` to `parse_talkbox_options` and the `ONBOX_*` variables to `TALKBOX_*` across the implementation and unit tests. This is a mechanical, behaviour-preserving rename.

## Related

- [Review: repository review](../reviews/repository-review.gen.md) (observation: `parse_onbox_options` is misleadingly named)
