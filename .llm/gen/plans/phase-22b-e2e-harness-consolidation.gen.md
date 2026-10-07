# Phase 22b: e2e setup/teardown consolidation and shared e2e helpers

#flow/pin #model/default

## scope

Resolves the e2e-side items of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md): §10 (setup/teardown boilerplate across the seven e2e files, per the selected [e2e setup/teardown mechanism choice](../../choices/e2e-setup-teardown-mechanism.gen.md)), §11 (`volume_mountpoint`/`container_stopped` defined per file), §12's e2e half (the logging shims that delegate to real podman — treated separately from the unit mock factory per the [shim factory interface choice](../../choices/shim-factory-interface.gen.md)), §14 (four HTTP readiness poll loops, per the selected [HTTP readiness wait placement choice](../../choices/http-readiness-wait-placement.gen.md)) and §15 (~16 hand-rolled `sdrun bash -c 'cd "$1" && …'` invocations, per the selected [e2e run wrapper mechanism choice](../../choices/e2e-run-wrapper-mechanism.gen.md)).

- Implemented in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash):
  - a shared `e2e_setup` performing the standard sequence (`mk_project`, `mk_talkbox`, `ensure_base_image_e2e`, project-slug and standard container-name derivation) and a shared `e2e_teardown` performing the standard cleanup (`teardown_talkbox`, removal of the project and talkbox trees), with registration helpers for extra directories to remove and host-server PIDs to kill (callable mid-test with registration clearing, matching the deny-allow/lifecycle pattern);
  - `volume_mountpoint` and `container_stopped` moved in from `git-transport.bats`/`merge-sync.bats`;
  - a standalone `wait_for_http <url>` helper with the current retry budget and sleep, replacing the four inline poll loops;
  - `run_talkbox` extended with an optional shim-directory (PATH-prepend) mechanism, plus one sibling helper for invoking talkbox through a differently-named executable (the symlink case);
  - one parameterised e2e-side logging-delegate helper (logging every invocation to a caller-supplied file, delegating everything else to the real podman, with the set of stubbed subcommands — e.g. `start`/`exec`/`stop` — as its only knob) replacing both `mk_gpu_shim` and the inline logging shims in [git-identity.bats](../../../test/e2e/git-identity.bats) and [deny-allow.bats](../../../test/e2e/deny-allow.bats). It stays independent of the unit mock factory: delegation to real podman never appears in `make_podman_shim`.
- Converted in the seven e2e files: every file's `setup()`/`teardown()` becomes a thin wrapper over the shared pair (adding its file-specific state: PATH exports, initial commits, ctr variables, tracked server PIDs); all hand-rolled `sdrun bash -c` sites in [onbox.bats](../../../test/e2e/onbox.bats) (3), [netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) (2), [deny-allow.bats](../../../test/e2e/deny-allow.bats) (3), [lifecycle.bats](../../../test/e2e/lifecycle.bats) (7) and [git-identity.bats](../../../test/e2e/git-identity.bats) (1) are routed through the shared helpers, removing their `# shellcheck disable=SC2016` comments; the four readiness loops become `wait_for_http` calls.
- Deferred: the container-fold repetition inside e2e tests (§16's `git-identity.bats` six-test fold) is handled by Phase 22c.

No aspect of `SPEC.md` changes. No production file is touched; external-facing behaviour is unchanged. The cleanup contract each file must honour (kill server, `teardown_talkbox`, `rm -rf`) becomes uniform, so a new e2e file no longer has to re-copy it correctly.

## files to be created

None. Modified: [test/e2e/helpers.bash](../../../test/e2e/helpers.bash), [test/e2e/onbox.bats](../../../test/e2e/onbox.bats), [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats), [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats), [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats), [test/e2e/git-identity.bats](../../../test/e2e/git-identity.bats), [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats), [test/e2e/merge-sync.bats](../../../test/e2e/merge-sync.bats). No `MAP.gen.md` update: `test/` is excluded from core files by `.coreignore`.

## relevant files to be read

- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) (existing helpers the new pair builds on: `mk_project`, `mk_talkbox`, `teardown_talkbox`, `ensure_base_image_e2e`, `start_host_http_server`, `run_talkbox`, `run_onbox_noninteractive`, `mk_gpu_shim`, `sdrun`)
- All seven e2e suites listed above (their current `setup()`/`teardown()` variance, hand-rolled invocation sites and readiness loops)
- [test/runner.mk](../../../test/runner.mk) (the `SHELL_SCRIPTS` lint/format surface covering `helpers.bash`)

## key internal interfaces

- `e2e_setup` / `e2e_teardown` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash): the shared pair sets/cleans the standard variables (`PROJECT`, `TALKBOX`, project slug, standard container names); registration helpers accept extra directories and server PIDs. Per-file `setup()`/`teardown()` keep their bats-mandated names and call the shared pair.
- `wait_for_http <url>`: retries with the current budget (20 × 0.5s) and succeeds when the URL responds; used immediately after `start_host_http_server`, including the IPv6 variant.
- `run_talkbox` keeps its `<project> <talkbox> [args…]` shape with an added optional shim-directory PATH-prepend; the new sibling helper covers invoking a differently-named (symlinked) executable from the project directory. `run_onbox_noninteractive` is unchanged.
- The new logging-delegate helper in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) keeps `mk_gpu_shim`'s observable contract (prints the shim directory, logs every invocation, delegates to the real podman except for its stubbed subcommands) as its stub-everything configuration; the `git-identity.bats`/`deny-allow.bats` inline shims are its stub-nothing configuration. It shares no code path with the unit `make_podman_shim`.

## consolidation guardrails

- The shared pair carries only the universal core (project/talkbox creation, base-image preparation, slug derivation; teardown_talkbox plus tree removal); anything file-specific stays in the file's own `setup()`/`teardown()` wrapper, which remains at the top of each file so the cleanup contract stays locally discoverable rather than hidden behind a convention.
- `e2e_teardown` must be safe when `setup()` failed partway — bats still invokes `teardown()` after a failed `setup()` — so it guards unset/empty variables before any `rm -rf` and tolerates missing resources; a half-created fixture must not turn a test failure into a cleanup hazard.
- Registration state is limited to extra directories and server PIDs; no general cleanup framework grows around it.
- `run_talkbox` gains only the single optional PATH-prepend plus the symlink sibling; no options parsing, so the wrapped command remains greppable at each call site.

## tests

Test-infrastructure restructuring only; no new product behaviour. The entire e2e suite is the safety net and must pass unchanged in its assertions — in particular the deny/allow enforcement tests (server start, readiness, kill) and the nft-installer test exercising the logging-delegate shim, the lifecycle tests, the interactive `expect` tests in [onbox.bats](../../../test/e2e/onbox.bats) (unaffected but re-verified), the `--gpu` tests on their new delegate helper, and the symlink-invocation test which moves onto the new sibling helper. No tests are superseded or removed: the setup/teardown wrappers, the readiness poll loops and the hand-rolled `sdrun` invocations being replaced are scaffolding inside or around tests, not tests themselves, and every test keeps its assertions. No existing test's assertions are weakened. `make lint` and `make format` must remain clean over the modified helpers and bats files. The full `make test-e2e` (and `make test-unit`) suites must pass at the end of the phase.
