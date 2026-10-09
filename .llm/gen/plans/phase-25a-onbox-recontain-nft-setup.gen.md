# Phase 25a: onbox `--recontain`/`--rebuild` install the nft deny rules and run `setup.sh`

#flow/redgreen #model/default

## aspect of the specification

Implements, for the recontain/rebuild path of `onbox`, the aspects of [SPEC.md](../../../SPEC.md) that are currently violated there:

- the network section: "For the `onbox` and `netbox` containers, the restrictions are enforced via `nft` before `image/setup.sh` is invoked" — currently `run_recreate` in [lib/containers.sh](../../../lib/containers.sh) skips both steps for `onbox` via nested `!= onbox` / `!= offbox` guards (lines 520-539).
- the dotfiles section: "After the container has been started, then `image/setup.sh` is invoked with `podman exec`" — currently not invoked at all for `onbox` on recontain/rebuild.

Nothing is deferred. This resolves [the issue](../issues/onbox-recontain-skips-nft-and-setup.gen.md) and is the prerequisite for the container consolidation (Phase 25b), which requires a single container-uniform start-time tail in `run_recreate`.

## external-facing functionality

`onbox --recontain` and `onbox --rebuild`, after starting the recreated container:

- install the nft deny/allow ruleset in the container's network namespace (when the effective deny set is non-empty), with the existing failure semantics of the create path — on failure the container is stopped and a `talkbox:` error raised;
- run `image/setup.sh` via `podman exec` (dotfiles, git identity, gitdir initialisation), as on the create path;
- then stop the container, as before.

`onbox` recontain/rebuild becomes behaviourally identical to `netbox`'s, and `run_recreate`'s start-time tail becomes structurally identical to `run_container`'s. `netbox`, `offbox` and all create-path behaviour are unchanged.

## design decision

Per [onbox `--recontain` start-time steps](../choices/onbox-recontain-start-steps.gen.md): align `run_recreate` with `run_container` — replace the nested guards with a single `!= offbox` guard around the nft install, followed by an unconditional `setup.sh` exec.

## files to be created

None.

## files to be modified

- [lib/containers.sh](../../../lib/containers.sh) — `run_recreate` only: the nested `!= onbox` / `!= offbox` block becomes the `run_container`-shaped tail (nft install unless offbox, then setup, then stop).
- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) — the two onbox `run_recreate` tests that pin the skip.
- [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) — the per-container `run_recreate` ordering loop test.
- [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats) — the onbox `--recontain` and `--rebuild` tests that pin the skip.
- [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) — extend the onbox `--recontain` e2e test to observe that setup ran.
- [MAP.gen.md](../../../MAP.gen.md) — the `lib/containers.sh` entry's description of `run_recreate`.

## relevant files to read during implementation

- [lib/containers.sh](../../../lib/containers.sh) — `run_recreate` (the nested guards), `run_container` (the reference tail), `install_nft_deny_or_die`, `run_setup_in_container`, `stop_container`.
- [lib/network.sh](../../../lib/network.sh) — `install_nft_deny` (empty deny set performs no invocation and cannot fail; strict/lax modes).
- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats) — the podman-shim harness and the tests pinning the current skip.
- [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats), [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — note the e2e setup empties the copied `defaults/deny.ip`, so the e2e recontain tests exercise an empty deny set and do not require `nft` on the host.
- [test/e2e/git-identity.bats](../../../test/e2e/git-identity.bats) — the pattern for observing that `setup.sh` completed (propagated git identity).
- [SPEC.md](../../../SPEC.md) — network and dotfiles sections.
- [.llm/gen/issues/onbox-recontain-skips-nft-and-setup.gen.md](../issues/onbox-recontain-skips-nft-and-setup.gen.md) — the issue being resolved.

## key internal interfaces

No signatures change. `run_recreate`'s post-plan tail becomes: `podman start` result from the plan, then the nft install guarded only by the offbox condition (i.e. the same applicability rule as `run_container`), then the setup exec, then the stop. The nested per-container asymmetry is deleted; no new internal interface is introduced.

## behavioural notes

- With an empty effective deny set (the e2e default), the nft step remains a no-op, so environments without `nft` are unaffected.
- `onbox --recontain`/`--rebuild` can now fail hard (container stopped, `talkbox:` error) when a non-empty deny set cannot be enforced — the same contract as `onbox` create.
- `setup.sh` running on onbox recontain re-applies dotfiles and re-wires the `host` remote in the freshly created gitdir volume; both are idempotent operations already exercised on every create.

## tests

Unit tests (podman-shim based) — the tests pinning the skip are superseded and rewritten to pin the new ordering:

- [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats): the recontain test "run_recreate onbox no removes, recreates and starts the onbox container, running no nft, setup or user command" and the rebuild test "run_recreate onbox yes builds the base image first..." — their `unshare`/`nsenter`/`exec` zero-count assertions are removed and replaced by assertions that the nft pipeline and the `setup.sh` exec appear, ordered `start` < nft < `setup.sh` < `stop` (both tests already pass a non-empty deny array).
- [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats): the data-driven loop test "run_recreate recontain and rebuild order start, the nft install, setup.sh and stop per container for netbox and offbox" is extended to include `onbox` (nft-before-setup column, like netbox).
- [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats): "talkbox.sh onbox --recontain recreates without populating, nft or setup" and "talkbox.sh onbox --rebuild builds the base image before recreating" — the zero-count assertions are replaced by presence and ordering assertions for `unshare nsenter` and `exec ... setup.sh` (retaining the no-populate, no-commit and build-ordering assertions).

End-to-end:

- [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats): the "onbox --recontain recreates the container and starts it" test additionally observes that setup ran in the recreated container (e.g. the host git identity propagated by `setup.sh` is present when the container is next used), mirroring the existing netbox recontain e2e check.

Completion requires `make test-unit`, `make test-e2e`, `make lint` and `make format` all green. On completion, mark the issue resolved in [.llm/gen/issues/INDEX.gen.md](../issues/INDEX.gen.md).
