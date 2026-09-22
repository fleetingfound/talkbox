# Choice: Eliminating the e2e shared-image inter-test coupling

## context

The review [test-suite-order-image-container-deps](../reviews/test-suite-order-image-container-deps.gen.md) identifies the single genuine inter-test coupling in the e2e suite: the shared `talkbox/base:latest` image. Two tests interact with it in ways that create cross-test dependence:

1. **`netbox-offbox.bats:156-165` (`netbox --rm-image removes the base image`)** destroys `talkbox/base:latest` as its final action. Every subsequent test in the same file (`--recontain`, `--rebuild`) and in lexicographically-later files (`onbox.bats`, `smoke.bats`) silently relies on `ensure_base_image` ([lib/containers.sh](../../../lib/containers.sh)) auto-rebuilding the image on demand. This works, but is a hidden coupling: if auto-rebuild ever breaks or slows, those tests fail for non-obvious reasons.

2. **`deny-allow.bats:162-196`** explicitly `podman build`s `talkbox/base:latest` and runs it directly via `podman run`, seeding buildah **external working containers**. Because `deny-allow.bats` sorts before `netbox-offbox.bats`, those artifacts are present when the later `--rm-image` test runs. Phase 16a's `prune_external_image_containers` ([lib/containers.sh](../../../lib/containers.sh) lines 216-223) now prunes them at `--rm-image` time, so this no longer causes failures — but the shared-state creation remains, and the prune is a mask rather than an elimination.

The review concludes: "Reordering the files would not eliminate the underlying hazard, only shift which test is exposed to it." This is true for the external-working-container hazard in isolation, but the coupling has two independent facets (image destruction + external-container seeding) and each can be eliminated at its source.

## goal

Eliminate (not mask) both coupling points so that:
- No test's correctness depends on another test having run or not run.
- The `--rm-image` test's destruction of the shared image does not affect any subsequent test.
- `deny-allow.bats`'s direct build does not leave shared state that any later test must work around.

## options

### Option 1: Reorder the `--rm-image` test to a last-sorting file + prune in `deny-allow.bats` teardown (Recommended)

Move the `netbox --rm-image removes the base image` test out of `netbox-offbox.bats` into a new file `test/e2e/zz-rm-image.bats`. The `zz-` prefix guarantees it sorts last lexicographically, so **no subsequent test** runs after the shared image is destroyed. This eliminates the "subsequent tests rely on auto-rebuild" coupling for both intra-file (`--recontain`, `--rebuild`) and inter-file (`onbox.bats`, `smoke.bats`) dependents.

Add a `teardown_file` to `deny-allow.bats` that prunes external working containers (`podman ps -a --external --filter ancestor=talkbox/base:latest` → `podman rm -f`) created by its direct `podman build`, making the file net-neutral on buildah artifacts. Phase 16a's `prune_external_image_containers` at `--rm-image` time remains as defence-in-depth.

- Eliminates both coupling points at their source.
- No new harness machinery (`setup_suite`/`teardown_suite`); uses only `teardown_file`, which bats has supported since 1.5.0 and which is already absent from the suite (so this introduces it in a single file).
- The `--rm-image` test is unchanged in content; only its file location moves.
- `deny-allow.bats`'s direct `podman build`/`podman run` is preserved (the test needs direct access to the base image to test nft deny in isolation); only its cleanup improves.
- Does not address cross-slug orphans from *other* test suites (mode 1 in [rm-image-e2e-failure](../reviews/rm-image-e2e-failure.gen.md)) — those are those suites' responsibility and are already refused by `image_in_use`.

### Option 2: Suite-level image lifecycle (`setup_suite` / `teardown_suite`)

Introduce `test/e2e/setup_suite.bash` with a `setup_suite` that builds `talkbox/base:latest` once (making image existence an explicit suite precondition) and a `teardown_suite` that removes the image and prunes external working containers + orphaned test containers referencing the base image. Still move the `--rm-image` test to a last-sorting file (mid-suite tests would otherwise run after the image is destroyed). `deny-allow.bats`'s explicit build becomes redundant (setup_suite guarantees the image) and can be dropped.

- Centralises the shared-image lifecycle at the suite boundary; the suite is net-neutral on podman state.
- `setup_suite` pre-building the image means the `ensure_base_image` auto-rebuild path is no longer exercised in e2e (only in unit tests), reducing integration coverage of that path.
- Introduces a new harness mechanism (`setup_suite`/`teardown_suite`) not used elsewhere in the suite.
- `teardown_suite` cleaning orphans referencing the base image is safe in a test context but conceptually broad.
- Larger structural change for a coupling that Option 1 eliminates with a file move.

### Option 3: Restore the image in the `--rm-image` test's teardown

Keep the `--rm-image` test in `netbox-offbox.bats`; after asserting the image is removed, rebuild it in teardown so subsequent tests find it present. Add the same `deny-allow.bats` teardown prune as Option 1.

- No reordering, no new files.
- Adds a `podman build` to every `--rm-image` test run (build time overhead, ~10-30s).
- The coupling is "restored" rather than eliminated: the test still destroys shared state mid-suite and depends on teardown running cleanly. If teardown fails (e.g. build error, timeout), subsequent tests break.
- Conceptually muddier: the test asserts the image is gone, then silently puts it back.

## recommendation

**Option 1.** It eliminates both coupling points at their source with the smallest, most targeted change: a file move (so no test runs after image destruction) and a `teardown_file` prune (so `deny-allow.bats` is net-neutral). It introduces no new harness machinery, preserves the `ensure_base_image` auto-rebuild integration coverage, and leaves Phase 16a's prune as defence-in-depth rather than the primary coupling mask.

## selected

**User-selected approach: a shared `ensure_base_image_e2e` helper function in `test/e2e/helpers.bash`, reused across tests.**

Rather than the three options above, the user chose a fourth approach: introduce a reusable helper function (e.g. `ensure_base_image_e2e <talkbox-dir>`) in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) that builds `talkbox/base:latest` from `$TALKBOX/image/Containerfile` if `podman image exists` returns false, and prunes external working containers after building to prevent accumulation. Each e2e file's `setup()` calls this helper, making the image-existence precondition **explicit per-test** rather than implicit.

This eliminates the coupling because:
- No test depends on another test having left the image present — each test's `setup()` explicitly ensures it.
- The `--rm-image` test can remain in `netbox-offbox.bats` because subsequent tests (`--recontain`, `--rebuild`, and all of `onbox.bats`/`smoke.bats`) call the helper in their `setup()` and rebuild if absent.
- `deny-allow.bats` replaces its inline `if ! podman image exists … podman build …` block (lines 167-169) with a call to the same helper, eliminating the duplicated build logic and the ad-hoc external-container seeding.
- The helper's post-build prune of external working containers prevents the buildah artifact accumulation that Phase 16a's `prune_external_image_containers` previously masked at `--rm-image` time; Phase 16a's prune remains as defence-in-depth.

The `--rm-image` test is unchanged in content and location. The `deny-allow.bats` direct `podman run talkbox/base:latest` (line 188) is preserved — the test needs direct access to the base image to test nft deny in isolation; only the build-and-check preamble is replaced by the helper.
