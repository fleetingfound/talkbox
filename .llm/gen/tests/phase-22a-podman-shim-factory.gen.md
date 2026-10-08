# Phase 22a test record: shared podman shim factory

Implements [Phase 22a](../plans/phase-22a-podman-shim-factory.gen.md), which extends the env-driven `make_podman_shim` factory in [test/unit/helpers.bash](../../../test/unit/helpers.bash) with the inspect-PID/exit/stderr and unshare-exit/stderr/PATH-log knobs needed to express every unit-side inline mock variant, and resolves the [`make_podman_shim` shadowing issue](../issues/make-podman-shim-shadowed-in-network-bats.gen.md) by deleting the `network.bats`-local factory and replacing all eleven inline mock-shim heredocs in `containers.bats`, `netbox-offbox.bats` and `lifecycle.bats` with factory calls.

## New tests

None. The phase adds no product behaviour and the plan explicitly adds no new tests; the existing assertions are the safety net for the restructure.

## Tests edited

No test's assertions were changed. The plan identifies the replaced shim code as test scaffolding, not tests: the deleted `network.bats`-local `make_podman_shim`, the eleven inline mock-shim heredocs and the per-test local `$log` files are replaced by shared-factory calls (`make_podman_shim` plus `PODMAN_*` knobs) and the shared `PODMAN_LOG`, with every explicit invocation sequence and assertion kept intact. Twenty tests had their scaffolding rewritten this way, none of which fails against the current implementation:

- `test/unit/network.bats` (9): the eight `install_nft_deny` strict/lax failure-mode and success tests now drive the shared factory via `PODMAN_INSPECT_RC`/`PODMAN_INSPECT_STDERR`, `PODMAN_UNSHARE_RC`/`PODMAN_UNSHARE_STDERR` and `PODMAN_UNSHARE_LOG` (mapped from the deleted local factory's `SHIM_*` variables), and the empty-deny no-invocation test uses a factory-constructed logging shim; the `SHIM_*` vocabulary and the shadowed definition are gone.
- `test/unit/containers.bats` (2): the nft-before-setup ordering test and the setup.sh-exec-failure test use the shared factory (`PODMAN_CONTAINERS` to reproduce the heredoc's everything-exists behaviour, `PODMAN_FAIL_PATTERN`/`PODMAN_FAIL_CODE` on `setup.sh` for the failure mode) with the default inspect PID `12345`.
- `test/unit/netbox-offbox.bats` (4): the netbox/offbox setup-ordering and recontain/rebuild-ordering tests use the shared factory (`PODMAN_CONTAINERS` where the heredoc made the container pre-exist), with the nsenter-absence assertions for offbox unchanged.
- `test/unit/lifecycle.bats` (5): the two `prune_external_image_containers` tests and the three `rm_image` pruning tests use the shared factory via `PODMAN_EXTERNAL` (the heredoc's `container exists … exit 1` behaviour is the factory default with an empty `PODMAN_CONTAINERS`).

The factory extension itself is documented at the factory in `test/unit/helpers.bash`: `PODMAN_INSPECT_PID` (default `12345`), `PODMAN_INSPECT_RC`/`PODMAN_INSPECT_STDERR` (PID-lookup failure mode), `PODMAN_UNSHARE_RC`/`PODMAN_UNSHARE_STDERR` (nft failure mode) and `PODMAN_UNSHARE_LOG` (per-unshare `PATH=` logging). The pre-existing `PODMAN_*` knobs and the always-on invocation logging are unchanged, and the factory remains a pure mock that never delegates to real podman.

## Tests removed

None. No test was superseded; the deleted local factory, heredocs and local log files were scaffolding only.

## Suite results

`make test-unit`: 305/305 pass (unchanged test count and names versus the pre-phase baseline). `make lint` and `make format` are clean over the modified files. `make test-e2e` was run as the whole-suite confirmation and passes 77/77; the phase touches no e2e file. (One earlier e2e run reported 23 transient failures caused by in-flight nested `systemd-run` podman units surviving the SIGTERM of an interrupted suite run; a clean re-run of the unmodified suite passed 77/77 both before and after this phase, and the anomaly is filed as [interrupted e2e suite run races the immediately following run](../issues/interrupted-e2e-suite-run-races-next-run.gen.md), which describes how a killed suite leaves nested `systemd-run` podman units running that make the next full run fail fast until they drain.)
