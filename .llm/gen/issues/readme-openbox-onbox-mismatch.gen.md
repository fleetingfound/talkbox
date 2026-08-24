# Issue: README.md refers to `openbox` instead of `onbox`

## Affected files

- [README.md](../../../README.md) — lines 14, 26, 27, 31, 35

## Description

The README.md uses the command name `openbox` (5 occurrences) to refer to the internet-enabled host-editing container. However, the actual command implemented by [talkbox.sh](../../../talkbox.sh), specified in [SPEC.md](../../../SPEC.md), indexed in [MAP.gen.md](../../../MAP.gen.md), and exercised by every test in [test/e2e/](../../../test/e2e), is `onbox` (not `openbox`).

For example, README.md line 14 reads:

> `openbox` creates a container which **allows** internet access and direct edits to `<project>/` on the host.

while SPEC.md line 11 reads:

> The command `onbox` creates a container which:
> - allows internet access
> - allows direct edits to `<project>/` on the host

A user reading the README would invoke `openbox` and receive `talkbox: unknown container: openbox` (exit code 2), since [talkbox.sh](../../../talkbox.sh) only accepts `onbox`, `netbox` and `offbox`.

## Suggested fix

Replace all 5 occurrences of `openbox` in [README.md](../../../README.md) with `onbox`. No code changes are required — the implementation, spec, and tests already use `onbox` consistently.

## Related

- [Review: current repository review](../reviews/repository-review.gen.md)
