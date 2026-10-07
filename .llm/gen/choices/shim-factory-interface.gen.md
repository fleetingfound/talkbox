# Podman shim factory interface

How the ~14 hand-written inline podman shims across the unit and e2e suites, the name-shadowing `make_podman_shim` in `test/unit/network.bats`, and `mk_gpu_shim` in `test/e2e/helpers.bash` are consolidated (review §12 and the [shadowing issue](../issues/make-podman-shim-shadowed-in-network-bats.gen.md)).

Most of the unit-suite inline shims are already expressible with the existing `PODMAN_*` knobs of the shared `make_podman_shim` (`test/unit/helpers.bash`): the PID-on-`inspect` variants print the same `12345` the shared shim already prints, the fail-on-`setup.sh` variants match `PODMAN_FAIL_PATTERN`/`PODMAN_FAIL_CODE`, and the `--external` listing variants match `PODMAN_EXTERNAL`. Only two families need genuinely new behaviour: the `network.bats` emulation of `inspect`/`unshare` failures (driven by `SHIM_*` variables) and the e2e logging shims that delegate to the real podman.

## Options

### A. Extend the env-driven shared shim (Recommended)

Extend `make_podman_shim` in `test/unit/helpers.bash` with the missing env-driven knobs — configurable `inspect` PID, exit code and stderr, and `unshare` emulation with configurable exit code/stderr and PATH logging — and use it at every mock-shim site. The local `make_podman_shim` in `network.bats` is deleted and its `SHIM_*` variables mapped onto the shared knobs (removing the shadowing).

Delegation to real podman is treated separately from the shim factory: the factory remains a pure mock that never touches real podman, and the e2e logging shims which wrap the real podman (with optional `start`/`exec`/`stop` stubbing) are consolidated into their own small e2e-side helper in `test/e2e/helpers.bash`.

- Pros: existing env-driven knobs already allow mid-test mutation, which several tests rely on (e.g. clearing `PODMAN_IMAGES` between two runs inside one test); the shadowing hazard is removed by deletion rather than renaming; one factory defines the mock's full behaviour surface while the mock/delegate distinction stays explicit.
- Cons: the shim script grows a few more branches; two helper families remain (unit mock, e2e delegate) rather than one.

### B. Flag-driven factory

Rebuild the factory as sketched in the review: `make_podman_shim <dir> [--pid N] [--fail-on <pattern>] [--external id…] [--delegate]`, with the knobs compiled into the shim at creation time.

- Pros: each shim's behaviour is visible at the call site; the shim script stays simple.
- Cons: mid-test mutation no longer fits (would need shim re-creation mid-test); a full interface rewrite of every existing call site for little gain over the env knobs.

### C. Minimal rename only

Rename the `network.bats`-local function (e.g. to `make_nft_shim`) to remove the shadowing hazard and leave the ~14 inline copies in place.

- Pros: smallest possible change; resolves the open issue in isolation.
- Cons: leaves the largest duplication cluster in the harness untouched; the issue's suggested fix explicitly points at the factory consolidation as the better resolution.

Selected: **A. Extend the env-driven shared shim**, with delegation to real podman treated separately per follow-up: the shared factory stays a pure unit-side mock, and the e2e logging-delegate shims (`mk_gpu_shim` and the inline copies in `git-identity.bats`/`deny-allow.bats`) are consolidated into a dedicated e2e-side helper.
