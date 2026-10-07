# Phase 22a: shared podman shim factory

#flow/pin #model/default

## scope

Resolves §12 of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md) for the **unit suite** (the largest single duplication cluster: the inline mock-shim heredocs) and the open issue [`make_podman_shim` is shadowed by a different implementation in `network.bats`](../../issues/make-podman-shim-shadowed-in-network-bats.gen.md), per the selected [shim factory interface choice](../../choices/shim-factory-interface.gen.md). Delegation to real podman is treated separately: the e2e logging-delegate shims are consolidated by Phase 22b, and the shared factory remains a pure mock that never invokes real podman.

- Implemented:
  - [test/unit/helpers.bash](../../../test/unit/helpers.bash): `make_podman_shim` is extended with the env-driven knobs needed to express every inline mock variant — configurable `inspect` PID (replacing the hardcoded `12345` as the default), configurable `inspect` exit code/stderr (the PID-lookup failure mode) and `unshare` emulation with configurable exit code/stderr (the `nft` failure mode) and PATH logging. The existing `PODMAN_*` knob semantics (containers/volumes/images existence, `inspect` running-state, `ps`/`--external` listing, `PODMAN_FAIL_PATTERN`/`PODMAN_FAIL_CODE`) are unchanged, as is the always-on invocation logging.
  - [test/unit/network.bats](../../../test/unit/network.bats): the file-local `make_podman_shim` (lines 334-363) is deleted; its `SHIM_*` variables are mapped onto the shared factory's knobs, and the `install_nft_deny` failure-mode tests use the shared shim. This removes the shadowing hazard and lets shared-shim improvements reach `network.bats`. The single remaining tiny logging shim (lines 386-390) also becomes a factory call.
  - [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats): all eleven inline mock-shim heredocs (PID-on-inspect, fail-on-`setup.sh`, `--external` listing variants) are replaced by `make_podman_shim` calls with the corresponding env knobs; the per-test local `$log` files become the shared `PODMAN_LOG`.
- Deferred to [Phase 22b](phase-22b-e2e-harness-consolidation.gen.md): the e2e logging shims that delegate to the real podman (`mk_gpu_shim` and the inline copies in `git-identity.bats`/`deny-allow.bats`), which become a dedicated e2e-side helper rather than a factory mode.

No aspect of `SPEC.md` changes. No production file under `talkbox.sh`, `lib/` or `image/` is touched; external-facing behaviour is unchanged.

## files to be created

None. Modified: [test/unit/helpers.bash](../../../test/unit/helpers.bash), [test/unit/network.bats](../../../test/unit/network.bats), [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats). No `MAP.gen.md` update: `test/` is excluded from core files by `.coreignore`. Upon completion, mark the shadowing issue resolved in [.llm/gen/issues/INDEX.gen.md](../../../.llm/gen/issues/INDEX.gen.md) with a link to this phase.

## relevant files to be read

- [test/unit/helpers.bash](../../../test/unit/helpers.bash) (the shared factory to be extended), [test/unit/network.bats](../../../test/unit/network.bats) (shadowed definition, `SHIM_*` knobs and the `install_nft_deny` tests that consume them), [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) (inline shim sites and their assertions)
- [lib/network.sh](../../../lib/network.sh) (the `inspect`/`unshare` invocation shapes the shim must emulate: `inspect -f {{.State.Pid}}`, `podman unshare nsenter -t <PID> -n nft -f -`)

## key internal interfaces

- `make_podman_shim <shimdir>` in [test/unit/helpers.bash](../../../test/unit/helpers.bash) keeps its signature; its env-driven knob vocabulary grows by the inspect-failure and unshare-emulation knobs described above. The default PID remains `12345` so existing assertions hold unless a test overrides it. The factory stays a pure mock: it never delegates to real podman.
- The `network.bats`-local `make_podman_shim` and its `SHIM_*` variables disappear; the affected tests set the shared knobs instead. The `path_without_sbin` helper stays as-is.

## consolidation guardrails

- The factory consolidates *shim construction only*; every test keeps its explicit invocation sequences and assertions, so a test's behaviour stays readable without knowing the factory internals.
- The knob vocabulary stays minimal and env-driven: only the inspect-PID/exit/stderr and unshare-exit/stderr/PATH-log knobs are added. The `unshare` emulation has a single consumer today and enters the factory only because folding it resolves the shadowing hazard; any future single-consumer behaviour that does not resolve a hazard stays local to its test.
- The knobs are documented at the factory in one place, so the supported mock surface stays discoverable; debuggability is preserved by the always-on invocation log.

## tests

This phase only restructures unit-test infrastructure; it adds no new product behaviour and no new tests. The existing unit suite is the safety net and must pass unchanged in its assertions: the `install_nft_deny` strict/lax failure-mode tests in `network.bats` (inspect and unshare failures, PATH visibility), the nft-before-setup ordering tests in `containers.bats`, and the external-container pruning tests in `lifecycle.bats` pin the replaced shims' behaviour.

No tests are superseded or removed: the deleted local `make_podman_shim`, the replaced heredocs and the per-test local `$log` files are test scaffolding, not tests. No existing test's assertions are weakened. `make lint` and `make format` must remain clean over the modified files. The full `make test-unit` suite must pass at the end of the phase (running `make test-e2e` as a whole-suite confirmation is encouraged but the phase touches no e2e file).
