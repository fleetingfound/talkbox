# `install_nft_deny` has no test for the non-empty deny install path or its warning

## Summary

`install_nft_deny` ([`lib/network.sh:135-152`](../../../lib/network.sh)) has three observable branches when the deny set is non-empty:

1. `podman inspect` fails to return a PID → warning at `:143`, return 0.
2. The `nft` install pipeline exits non-zero → warning at `:149`, return 0.
3. The `nft` install pipeline succeeds → no warning, return 0.

None of these branches is exercised by the current test suite:

- The only `install_nft_deny` unit test ([`test/unit/network.bats:295-311`](../../../test/unit/network.bats)) covers the *empty-deny-set* early-return path, which performs no `podman` invocation at all.
- The e2e tests in [`test/e2e/deny-allow.bats`](../../../test/e2e/deny-allow.bats) exercise the real install path but are gated behind `require_nft_and_internet` / `require_nft_ipv6` and silently skip on hosts without `nft`/IPv6/internet — i.e. exactly the hosts on which the warning fires. None of the passing-path e2e tests asserts the *absence* of the warning on stderr either, so a regression that silently falls back to warn-and-continue would not be detected.

The planned unit test "`install_nft_deny` warns and returns success when the rules cannot be applied" is described in [`.llm/gen/tests/phase-12c-ip-deny-allow-enforcement.gen.md`](../tests/phase-12c-ip-deny-allow-enforcement.gen.md) but was never implemented.

## Why it matters

The warn-and-continue semantics are a documented security-relevant choice (see [`ip-deny-allow-enforcement.gen.md`](../choices/ip-deny-allow-enforcement.gen.md)). Because the behaviour is unverified:

- a refactor that accidentally changes the return value, suppresses the warning, or inverts the success/failure condition would not be caught; and
- users investigating the warning have no test to point at to confirm the intended behaviour.

## Suggested coverage

Add unit tests in `test/unit/network.bats` using a fake `podman` on `PATH` (the same shim pattern already used by the empty-deny-set test) covering:

- `install_nft_deny` with a non-empty deny set and a `podman inspect` that succeeds but a pipeline that exits non-zero → asserts the line-149 warning is emitted on stderr and the function returns 0.
- `install_nft_deny` with a non-empty deny set and a `podman inspect` that exits non-zero → asserts the line-143 warning is emitted and the function returns 0.
- `install_nft_deny` with a non-empty deny set and a pipeline that succeeds → asserts no warning is emitted and the function returns 0.

Additionally, an e2e assertion that the passing-path `onbox`/`netbox` deny runs emit *no* `talkbox: warning: cannot apply nftables` line on stderr would catch silent-fallback regressions on hosts where `nft` is available.

## Files

- [`lib/network.sh`](../../../lib/network.sh) (`:135-152`)
- [`test/unit/network.bats`](../../../test/unit/network.bats) (`:295-311`)
- [`test/e2e/deny-allow.bats`](../../../test/e2e/deny-allow.bats)
- [`.llm/gen/tests/phase-12c-ip-deny-allow-enforcement.gen.md`](../tests/phase-12c-ip-deny-allow-enforcement.gen.md)

## Related review

- [nftables deny/allow install failure — warning, test gap, and fail-hard consideration](../reviews/nftables-deny-install-warning.gen.md)
