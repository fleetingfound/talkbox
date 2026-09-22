# Review: Test-suite order, image, and container dependencies

## scope

This review assesses three properties of the talkbox test suite under `test/`:

1. The extent to which tests depend on other tests having already run (inter-test ordering coupling).
2. Whether tests assume pre-existing podman **images**.
3. Whether tests assume pre-existing podman **containers**.

It draws on every `.bats` file in `test/unit`, `test/e2e`, `test/canary` and `test/timeout`, the shared helpers (`test/unit/helpers.bash`, `test/e2e/helpers.bash`), the runner (`test/run-suite.sh`), and `test/runner.mk`. It complements, but does not repeat, the narrower diagnosis in [rm-image-e2e-failure](rm-image-e2e-failure.gen.md).

## harness execution model

`test/run-suite.sh:25` collects every `*.bats` file in the suite directory via `find … | sort` and passes them in one shot to a **single** `bats --tap "$@"` invocation. Consequences:

- All tests in a suite share one long-lived bats process and one shared podman storage state.
- File execution order is lexicographic:
  - **unit**: `bashrc, common, containers, git, git-transport, lifecycle, merge, mounts, naming, netbox-offbox, network, options, smoke`
  - **e2e**: `deny-allow, git-identity, git-transport, lifecycle, merge-sync, netbox-offbox, onbox, smoke`
- No `setup_file`/`teardown_file` exists anywhere in the suite (confirmed by grep), so there is no per-file shared fixture — only per-test `setup()`/`teardown()`.

## unit suite — fully hermetic

Every unit test that touches podman does so through a `PATH`-prepended **podman shim** (e.g. `make_podman_shim` in `test/unit/network.bats`, the inline shims in `test/unit/containers.bats`, `test/unit/lifecycle.bats`, `test/unit/netbox-offbox.bats`, `test/unit/git-transport.bats`). No real image is built, no real container is created or assumed. Planner tests reference `talkbox/base:latest` and `<slug>.netbox.root` purely as **string tokens** inside expected argument arrays — not as images that must exist.

`setup()` functions in `test/unit/{options,mounts,network,git,merge,lifecycle,containers,netbox-offbox,git-transport}.bats` create per-test state under `$BATS_TEST_TMPDIR` only; `teardown` is implicit (bats removes the tmpdir). `test/unit/{smoke,common,bashrc,naming}.bats` define no `setup`/`teardown`.

**Conclusion for the unit suite: no inter-test dependencies; no image-existence assumptions; no container-existence assumptions; execution order is irrelevant.**

## e2e suite — per-test container isolation, one shared global image

### per-test container isolation is real

Each e2e `setup()` (`test/e2e/{git-identity,onbox,lifecycle,merge-sync,netbox-offbox,git-transport,deny-allow}.bats`) calls `mk_project` (`test/e2e/helpers.bash:15-22`), which `mktemp -d`s a fresh directory and `git init`s it. The directory's basename drives `project_slug_e2e` (`test/e2e/helpers.bash:67-78`), so every test gets a unique slug and therefore unique container names (`<slug>.onbox`, `<slug>.netbox`, `<slug>.offbox`), unique root-image names (`<slug>.netbox.root`, `<slug>.offbox.root`) and unique volumes (`<slug>.*`).

Each `teardown()` calls `teardown_talkbox` (`test/e2e/helpers.bash:51-65`), which force-removes those containers, rmi's the per-slug root images, and removes every volume whose name matches the slug.

**Consequence:** no e2e test assumes that a container created by an earlier test (in the same file or another file) still exists. Every container a test uses, it creates itself within the test body. Cross-invocation container reuse within a single test (e.g. `test/e2e/lifecycle.bats:37-43` "onbox -c <command> runs within the same persistent container", which reads a probe file written by the previous invocation into the still-stopped persistent container) is internal to that test and torn down by `teardown_talkbox`.

### the one genuine cross-test dependency: the shared `talkbox/base:latest` image

`teardown_talkbox` deliberately does **not** remove `talkbox/base:latest` — it is the global shared base image built from [image/Containerfile](../../../image/Containerfile). This is the single persistent resource that crosses test boundaries in the e2e suite.

Two tests interact with that shared image in ways that create inter-test coupling:

#### 1. `test/e2e/netbox-offbox.bats:156-165` — destroys the shared image

```bash
@test "netbox --rm-image removes the base image" {
  run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'true'
  [[ "$status" -eq 0 ]]
  run sdrun podman image exists talkbox/base:latest
  [[ "$status" -eq 0 ]]
  run run_talkbox "$PROJECT" "$TALKBOX" netbox --rm-image
  [[ "$status" -eq 0 ]]
  run sdrun podman image exists talkbox/base:latest
  [[ "$status" -ne 0 ]]
}
```

- This test does **not** assume a pre-existing image — its first assertion checks for presence and the test itself calls `netbox` first, which triggers `ensure_base_image` ([lib/containers.sh:172-176](../../../lib/containers.sh)) and builds the image if absent.
- It does, however, **destroy** `talkbox/base:latest` as its final action. Every subsequent test in the suite (`netbox --recontain` at line 167, `netbox --rebuild` at 179, and all of `onbox.bats` and `smoke.bats`, which sort lexicographically **after** `netbox-offbox.bats`) silently relies on `ensure_base_image` rebuilding the image on demand. The suite only passes because that auto-rebuild is reliable on a clean host.
- The `--rm-image` removal itself only succeeds when `image_in_use` ([lib/containers.sh:204-214](../../../lib/containers.sh)) returns false, i.e. when **no other container** — including orphaned containers left behind by an interrupted prior run, or buildah **external working containers** seeded by an earlier `podman build` — references the base image. This is the failure mode already documented in [rm-image-e2e-failure](rm-image-e2e-failure.gen.md) and in the resolved issue [rm-image-blocked-by-external-working-containers](../issues/rm-image-blocked-by-external-working-containers.gen.md); the `prune_external_image_containers` helper ([lib/containers.sh:216-223](../../../lib/containers.sh)) exists specifically to mask this cross-file ordering hazard.

#### 2. `test/e2e/deny-allow.bats:162-196` — rebuilds the shared image and runs it directly

```bash
@test "onbox --deny-ip blocks a deny-listed connection attempted during setup" {
  require_nft_and_internet
  ...
  if ! sdrun podman image exists talkbox/base:latest >/dev/null 2>&1; then
    sdrun podman build -t talkbox/base:latest -f "$TALKBOX/image/Containerfile" "$TALKBOX/image" >/dev/null
  fi
  ...
  sdrun podman run --rm -i --network=none --userns=keep-id:uid=1000,gid=1000 \
      -v "$vol:/v" -v "$cfg:/cfg:ro" talkbox/base:latest cp /cfg /v/config
  ...
}
```

- This is the **only** e2e test that explicitly checks-and-builds `talkbox/base:latest` itself, and the **only** e2e test that runs `podman run talkbox/base:latest` directly (rather than going through `talkbox.sh`, which auto-builds). So it does **not** depend on a pre-existing image — it self-guards.
- However, its `podman build` seeds buildah external working containers; because `deny-allow.bats` sorts **before** `netbox-offbox.bats`, those artifacts are present when the later `netbox --rm-image` test runs and historically caused it to fail until `prune_external_image_containers` was added. This is a real cross-file ordering dependency, currently masked by the prune helper rather than eliminated.

### image-existence and container-existence assumptions in the e2e suite

| assumption | present? | evidence |
|---|---|---|
| Test assumes a pre-existing **image** it did not build | **No** | Every test path that consumes `talkbox/base:latest` goes through `talkbox.sh`, which calls `ensure_base_image` (auto-build-on-absent). The one direct `podman run talkbox/base:latest` (`deny-allow.bats:188`) self-guards with an explicit `podman image exists` + `podman build`. Per-slug root images (`<slug>.netbox.root` etc.) are always produced by the test's own `--rebuild`/`--recontain` flow, never assumed pre-existing. |
| Test assumes a pre-existing **container** it did not create | **No** | Every `podman exec`/`start`/`stop`/`rm` against `<slug>.onbox`/`netbox`/`offbox` is preceded within the same test by a `talkbox.sh` invocation that creates the container. Cross-invocation reuse within one test (e.g. `lifecycle.bats:37-43`, several `merge-sync.bats` tests) is between runs of the same test, not across tests. |
| Test **destroys** shared cross-test state | **Yes** | `netbox --rm-image` (above) removes `talkbox/base:latest`. |
| Test **creates** shared cross-test state | **Yes** | `deny-allow.bats:167-169` rebuilds `talkbox/base:latest` (and seeds buildah external working containers). |

## canary and timeout suites

`test/canary/false.bats` and `test/timeout/hang.bats` define no `setup`/`teardown`, touch no podman, and are intentionally-failing harness checks run via the separate `make test-canary`/`test-timeout` targets. Fully self-contained; no ordering, image, or container dependencies.

## summary

- **Inter-test ordering coupling:** none in the unit suite; none in the canary/timeout suites. In the e2e suite the **only** genuine inter-test coupling is via the single shared `talkbox/base:latest` image: `deny-allow.bats` rebuilds it (seeding buildah external working containers) and `netbox-offbox.bats:156-165` later destroys it, with the latter depending on the absence of orphaned/external containers referencing the base image. This coupling is currently masked by `prune_external_image_containers` ([lib/containers.sh:216-223](../../../lib/containers.sh)) and by `ensure_base_image`'s auto-rebuild-on-absent behaviour.
- **Image-existence assumptions:** none. No test relies on `talkbox/base:latest` or any `<slug>.*.root` image being pre-present; every consumer path auto-builds on demand, and the one direct consumer self-guards with an explicit check-and-build.
- **Container-existence assumptions:** none. Every container a test uses is created within that same test (typically by a `talkbox.sh` invocation earlier in the test body), and `teardown_talkbox` removes all per-slug containers, root images, and volumes at the end of each test.
- **Does execution order matter?** For correctness of an individual test in isolation: no, except that `netbox-offbox.bats:156-165`'s success probability is influenced by preceding `podman build` activity in `deny-allow.bats` (which seeds external working containers). For suite-level flakiness: yes — the lexicographic file ordering plus the single shared bats process mean any orphaned container or external working container left behind by an interrupted run can cause `netbox --rm-image` to fail. Reordering the files would not eliminate the underlying hazard, only shift which test is exposed to it.

The narrow failure mode of `netbox --rm-image` is analysed in detail in [rm-image-e2e-failure](rm-image-e2e-failure.gen.md) and tracked by the resolved issue [rm-image-blocked-by-external-working-containers](../issues/rm-image-blocked-by-external-working-containers.gen.md); this review does not repeat that analysis but situates it as the sole concrete manifestation of the e2e suite's shared-image coupling.
