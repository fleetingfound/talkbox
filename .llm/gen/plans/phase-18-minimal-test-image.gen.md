# Plan: Phase 18 — Minimal test Containerfile for the e2e suite

#flow/unified #model/default

## Specification scope

No functional aspect of `SPEC.md` / `SPEC.gen.md` is implemented or altered. This phase is a test-infrastructure change that makes the e2e suite build and use a dedicated minimal base image instead of the production image, per the design selected in:

- [minimal-test-image-tag-isolation](../choices/minimal-test-image-tag-isolation.gen.md)
- [minimal-test-containerfile-placement](../choices/minimal-test-containerfile-placement.gen.md)
- [minimal-test-image-content](../choices/minimal-test-image-content.gen.md)

The SPEC's testing requirements are preserved unchanged: bats-core suites invoked via `make test-unit` / `make test-e2e`, every podman-touching invocation wrapped in `systemd-run` with `RuntimeMaxSec` and `KillMode=control-group`, temporary git/non-git projects as `<project>` stand-ins, noninteractive-by-default with `expect`-driven interactive tests, and no GPU tests. The SPEC's image contract is preserved for the test image: it still includes `image/setup.sh`, the `dev` user (uid/gid 1000) and `/working`, so the containers the suite exercises remain spec-shaped.

The only production-code change is an internal environment hook: `base_image_name()` honours `TALKBOX_BASE_IMAGE`, defaulting to the current `talkbox/base:latest`. This follows the existing `TALKBOX_ROOT` / `TALKBOX_STRICT_NFT` env-hook precedent. The production [image/Containerfile](../../../image/Containerfile) and default image behaviour are unchanged and are no longer built by any test.

## To be deferred

- A production `--base-image` CLI option or documentation of `TALKBOX_BASE_IMAGE` as a user-facing knob. The hook remains an internal/testability escape hatch.
- Any staleness invalidation of the cached test image beyond the current existence check (e.g. content hashing of `image/Containerfile.minimal` to force rebuilds). `ensure_base_image_e2e` keeps its build-if-absent semantics; the `netbox --rm-image` e2e test still removes the test tag, and later setups rebuild it cheaply.
- Making the e2e suite run without network on first run. Building the test image still requires internet (pulling `debian:trixie-slim` plus one small apt layer), as the current production-image build does; once built, the image is cached across runs.

## External-facing functionality

- For end users: none beyond the internal hook — `base_image_name()` returns `TALKBOX_BASE_IMAGE` when set, `talkbox/base:latest` otherwise.
- For the test suite: e2e tests build a minimal Debian-slim image (git, curl, ca-certificates, the `dev` user, `/working`, `setup.sh`) under a dedicated test tag instead of the production image, so e2e setup no longer downloads editors, runtimes and coding agents; the user's production `talkbox/base:latest` is never built, retagged or removed by tests, and tests never silently run against a pre-existing user image.

## Files to be created

- `image/Containerfile.minimal` — the minimal test image definition, mirroring the production image's structure minus everything the suite does not exercise:
  - `FROM debian:trixie-slim`, `ENV LANG=C.UTF-8`
  - `apt-get install` of only `git`, `curl`, `ca-certificates` (no recommends; `bash`, coreutils, `grep`, `findutils`, `clear`'s `ncurses-bin` are required-priority in the Debian base)
  - the `dev` group/user with uid/gid 1000 and bash shell; `install -d -o dev -g dev /working`
  - `COPY --chmod=755 setup.sh /usr/local/bin/setup.sh`, `USER dev`, `WORKDIR /working`
  - no sudo, `less`, neovim, tmux, fzf, tree, wget, node, npm, uv, python or coding agents

## Files to read during implementation

- [image/Containerfile](../../../image/Containerfile) and [image/setup.sh](../../../image/setup.sh) — the structure to mirror (user creation, `/working`, setup.sh COPY).
- [lib/naming.sh](../../../lib/naming.sh) — `base_image_name()` to modify.
- [lib/containers.sh](../../../lib/containers.sh) — the base-image consumers that must transparently follow the override: the three `podman build` sites (`plan_rebuild`, the netbox/offbox rebuild planners, `ensure_base_image`), `inherit_source`, `container_sync_cmd`, `plan_rm_image`; no edits needed there beyond confirming they all call `base_image_name()`.
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — `mk_talkbox` (Containerfile swap), `sdrun` (env forwarding), `ensure_base_image_e2e` (tag), `teardown_talkbox` (unchanged; does not remove the base image).
- [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats) and [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) — direct `talkbox/base:latest` references to retarget.
- [test/unit/naming.bats](../../../test/unit/naming.bats) — the existing default-tag pin; where the override unit test is added.
- [MAP.gen.md](../../../MAP.gen.md) — entries to add/update.

## Files to be modified

- `lib/naming.sh` — `base_image_name()` returns `${TALKBOX_BASE_IMAGE:-talkbox/base:latest}`.
- `test/e2e/helpers.bash`:
  - a dedicated e2e base-image tag constant (e.g. `talkbox/base-e2e:latest`);
  - `sdrun` forwards `TALKBOX_BASE_IMAGE` (set to the test tag) into the systemd-run unit environment alongside `PATH`, covering helper-driven runs, inline `sdrun bash -c` invocations (symlink, `--command`, GPU-shim tests) and `expect`-driven interactive tests (children of the unit environment);
  - `mk_talkbox` overwrites the temp copy's `image/Containerfile` with the repository's `image/Containerfile.minimal` after the tree copy, so every test-reachable build path builds the minimal image;
  - `ensure_base_image_e2e` builds/tags the minimal image with the test tag and prunes external working containers with the `ancestor=` filter on the test tag.
- `test/e2e/deny-allow.bats` — the direct `podman run ... cp` gitdir-config seeding uses the test tag.
- `test/e2e/netbox-offbox.bats` — the `podman image exists` assertions around `netbox --rm-image` use the test tag.
- `test/unit/naming.bats` — new unit test: `base_image_name` returns the override when `TALKBOX_BASE_IMAGE` is set and the default otherwise (unset/restore the variable so the existing default-pin test is unaffected).
- `MAP.gen.md` — add `image/Containerfile.minimal`; update the `lib/naming.sh` entry to mention the `TALKBOX_BASE_IMAGE` override.

## Key internal interfaces

- `base_image_name()` (lib/naming.sh): contract change — returns `TALKBOX_BASE_IMAGE` when set, `talkbox/base:latest` otherwise. All existing consumers (the create/rebuild planners, `ensure_base_image`, `inherit_source` root-image fallback, `container_sync_cmd` and the `plan_fetch` bundle container, `plan_rm_image`) pick up the override with no further changes, since they all call this single function.
- `sdrun()` (test/e2e/helpers.bash): contract change — the systemd-run unit environment includes `TALKBOX_BASE_IMAGE=<test tag>` in addition to `PATH`.
- `mk_talkbox()` (test/e2e/helpers.bash): contract change — the temp talkbox copy's `image/Containerfile` is the minimal test definition; the build context (the temp `image/` directory) still contains `setup.sh` for the `COPY`.
- `ensure_base_image_e2e()` (test/e2e/helpers.bash): contract change — ensures the minimal test image exists under the test tag (build from `$talkbox/image/Containerfile` if absent); the external-container prune filters by the test tag.
- `teardown_talkbox()` (test/e2e/helpers.bash): unchanged — it removes only per-project containers, root images and volumes, so the test base image stays cached across tests and runs; after the `netbox --rm-image` test removes the test tag, subsequent setups rebuild it cheaply via `ensure_base_image_e2e`.

## Tests

Requires tests:

- **Unit tests** (`make test-unit`): `base_image_name()` returns the default `talkbox/base:latest` when `TALKBOX_BASE_IMAGE` is unset and the override value when it is set, in `test/unit/naming.bats`. The existing unit tests that pin the default tag in expected plan arrays (`lifecycle.bats`, `git-transport.bats`) are unaffected and must keep passing unmodified.
- **End-to-end tests** (`make test-e2e`): the existing e2e suite in its entirety is the validation — it exercises every in-container need the minimal image must satisfy (bash/git/`git-upload-pack`/curl/coreutils, the `dev` user, `/working`, the setup.sh image contract, dotfiles, internet probes, deny/allow) and the lifecycle verbs (`--rebuild`, `--rm-image`, root-image inheritance) against the test tag. Only the retargeted direct image references change; no new e2e tests are required beyond the retargeting.
- No GPU tests (per spec).

## Verification

- `make lint` and `make format` (helpers.bash and the bats files are already covered by `SHELL_SCRIPTS`; no runner.mk change needed since the Containerfile is not a shell script).
- `make test-unit` passes with the new naming override test.
- `make test-e2e` passes in full against the minimal image.
- After an e2e run: `podman image exists talkbox/base-e2e:latest` succeeds, and any pre-existing production `talkbox/base:latest` is untouched by the suite.
