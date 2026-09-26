# Build: Phase 18 — Minimal test Containerfile for the e2e suite

This build implements [phase-18-minimal-test-image.gen.md](../plans/phase-18-minimal-test-image.gen.md): the e2e suite now builds and exercises a dedicated minimal Debian-slim base image (`talkbox/base-e2e:latest`, git + curl + ca-certificates + the spec-shaped `dev` user/`/working`/`setup.sh` contract) instead of the heavy production image, selected via an internal `TALKBOX_BASE_IMAGE` env hook on `base_image_name()` plus a temp-copy Containerfile swap in `mk_talkbox`, so tests never build, retag or remove the user's production `talkbox/base:latest`.

## Changes

- `image/Containerfile.minimal` (new) - minimal test image definition mirroring the production image's structure (`FROM debian:trixie-slim`, `ENV LANG=C.UTF-8`, `dev` group/user uid/gid 1000 with bash shell, `COPY --chmod=755 setup.sh`, `install -d -o dev -g dev /working`, `USER dev`, `WORKDIR /working`) with a single apt layer installing only `ca-certificates curl git` (no recommends) — no sudo, editors, terminal tools, runtimes or coding agents.
- `lib/naming.sh` - `base_image_name()` returns `${TALKBOX_BASE_IMAGE:-talkbox/base:latest}`; the only production-code change, following the existing `TALKBOX_ROOT`/`TALKBOX_STRICT_NFT` env-hook precedent. All base-image consumers (create/rebuild planners, `ensure_base_image`, `inherit_source` fallback, `container_sync_cmd`/`plan_fetch`, `plan_rm_image`) flow through this one function and pick up the override unchanged (confirmed: no edits needed in `lib/containers.sh`/`lib/git.sh`).
- `test/e2e/helpers.bash` - added the `E2E_BASE_IMAGE='talkbox/base-e2e:latest'` tag constant; `sdrun` forwards `TALKBOX_BASE_IMAGE` into every systemd-run unit environment alongside `PATH` (covering helper-driven, inline `bash -c` and `expect`-driven invocations); `mk_talkbox` overwrites the temp copy's `image/Containerfile` with the repository's `image/Containerfile.minimal` after the tree copy, so every test-reachable build path (`ensure_base_image`, `plan_rebuild`, the netbox/offbox rebuild planners) builds the minimal image while the `image/` context still provides `setup.sh`; `ensure_base_image_e2e` builds/checks/prunes against the test tag.
- `test/e2e/deny-allow.bats` - the direct `podman run ... cp` gitdir-config seeding uses `$E2E_BASE_IMAGE`.
- `test/e2e/netbox-offbox.bats` - the `podman image exists` assertions around `netbox --rm-image` use `$E2E_BASE_IMAGE`.
- `test/unit/naming.bats` - new unit test `base_image_name honours the TALKBOX_BASE_IMAGE override and the default when unset` (sets the variable, asserts the override, unsets it, asserts the default; the variable is per-test-subshell so the existing default-pin test is unaffected).
- `MAP.gen.md` - added `image/Containerfile.minimal`; updated the `lib/naming.sh` entry to mention the override.

## Edited-test justifications

- `test/e2e/deny-allow.bats` — `require_nft_ipv6()` gained a skip guard. Error in the test suite's implementation: the guard only checked that the host can *bind* `::1` (which succeeds even on IPv6-less hosts), while the actual precondition of the tests it guards is that pasta forwards IPv6 — pasta binds `-T` forwarded ports on the container's `::1` only when the host's outbound interface has a global IPv6 address at container start, otherwise the in-container `curl` to `http://[::1]:<port>/` fails with `curl: (7)` and the test fails instead of skipping. This violated the suite's own established convention, evidenced by the sibling guard in the same file: `require_nft_and_internet()` skips with `"host has no internet connectivity; skipping the deny/allow e2e test"` when the environment cannot support the test — mirroring SPEC.md's environment-awareness principle ("Do not write tests for GPU usage, since a GPU may not be available on all systems where tests are run", SPEC.md line 405). Evidence for the error: the failing test reproduced identically on the pre-change code with the production image (`git stash` run), a bare `podman run --network="pasta:-T,<port>"` with no talkbox code reproduced it, and temporarily adding a global IPv6 address to the host's outbound interface made pasta bind `::1:<port>` in the container netns (`/proc/net/tcp6` LISTEN on `0000...0001`) and the container curl succeed — proving the guard checked the wrong (insufficient) condition. The plan's verification requirement ("`make test-e2e` passes in full against the minimal image", plan L80) is otherwise unsatisfiable on this host. The retargeting of `deny-allow.bats`' direct `podman run` reference is plan-mandated (plan L55) and not a behavioural test edit.

## Verification

- `make lint` and `make format` pass (no reformats).
- `make test-unit`: 278/278 pass, including the new `base_image_name` override test; the plan-pinned default-tag unit tests (`lifecycle.bats`, `git-transport.bats`) pass unmodified.
- `make test-e2e`: 76 total, 75 pass, 0 fail, 1 skip (the IPv6 loopback deny/allow test, skipped by the corrected guard because the host currently has no global IPv6 address; it failed identically on the unmodified pre-change code with the production image), exit 0.
- After the e2e run: `podman image exists talkbox/base-e2e:latest` succeeds, and the pre-existing production `talkbox/base:latest` is untouched (image ID `b452b0900480…` unchanged before and after the suite).

## Deferred (per plan)

- No production `--base-image` CLI option or user-facing documentation of `TALKBOX_BASE_IMAGE`.
- No staleness invalidation of the cached test image beyond the existence check; `ensure_base_image_e2e` keeps build-if-absent semantics.
- No network-free first run; the test image build still pulls `debian:trixie-slim` plus one small apt layer.
