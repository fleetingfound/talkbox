# Choice: Placement and selection of the minimal test Containerfile

## context

The test suite needs a minimal Containerfile (instead of the production [image/Containerfile](../../../image/Containerfile)) from which the e2e base image is built. Every build path in the implementation builds from `$TALKBOX_ROOT/image/Containerfile` with context `$TALKBOX_ROOT/image` (three `podman build` sites in [lib/containers.sh](../../../lib/containers.sh): `plan_rebuild`, the `netbox`/`offbox` rebuild planners, and `ensure_base_image`). In e2e tests, `TALKBOX_ROOT` is the per-test temp talkbox copy created by `mk_talkbox` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash), which copies `image/` (Containerfile + `setup.sh`) from the repository.

The selection mechanism must cover **all** build paths reachable in tests, notably the e2e `--rebuild` tests which invoke `podman build` unconditionally from `$TALKBOX_ROOT/image/Containerfile` — if the temp copy still contains the production Containerfile, those tests build the heavy image (multi-minute, network-heavy). The context directory must also contain `setup.sh`, since the image contract (`COPY setup.sh /usr/local/bin/setup.sh`) is part of the spec's image description.

## options

### Option 1: `test/e2e/Containerfile`, swapped into the temp talkbox copy by `mk_talkbox` (Recommended)

The minimal Containerfile lives in the repo as a test fixture (e.g. `test/e2e/Containerfile`). `mk_talkbox` overwrites the temp copy's `image/Containerfile` with it after the `cp -a` of the repository tree. The build context remains the temp `image/` directory, which already contains `setup.sh`.

- One swap point covers every build path: `ensure_base_image`, `plan_rebuild` and the `netbox`/`offbox` rebuild planners all build the minimal image because they read `$TALKBOX_ROOT/image/Containerfile` from the temp copy.
- `ensure_base_image_e2e` keeps building from `$talkbox/image/Containerfile` unchanged — it picks up the minimal file automatically.
- The production `image/Containerfile` is never touched and never built by tests.
- The fixture lives next to its only consumer (the e2e suite).

### Option 2: `image/Containerfile.test` built directly by `ensure_base_image_e2e`

Store the minimal file next to the production Containerfile and have the e2e helper build it directly with an explicit `-f`.

- No `mk_talkbox` change for the ensure path.
- The e2e `--rebuild` tests still build the production Containerfile from the temp copy (the heavy image), unless the implementation additionally grows a Containerfile-path override — defeating the purpose.
- Places a test fixture inside the production image directory, blurring the production/test boundary.

### Option 3: implementation env-var override for the Containerfile path

Add a `TALKBOX_CONTAINERFILE`-style env hook in `lib/containers.sh` so the build sites read the Containerfile path (and matching context) from the environment; tests point it at the minimal file in the repository.

- No temp-copy swap; the repository file is used in place.
- More implementation surface than a tag override: three build sites must honour both path and context, and the context must contain `setup.sh` — forcing either a duplicated `setup.sh` beside the test fixture or context juggling.
- The rebuild planners would build with a context outside `$TALKBOX_ROOT/image`, a shape the implementation never has today.

## recommendation

**Option 1.** The temp-copy swap is the smallest mechanism that covers every build path reachable in tests (including the unconditional `--rebuild` builds), requires no new implementation hooks beyond the image tag, keeps the build context semantics (`image/` containing `setup.sh`) intact, and keeps the production Containerfile entirely out of the test path.

## selected

**User-selected location: `image/Containerfile.minimal`, next to the production Containerfile — selected via the Option 1 temp-copy swap mechanism.**

The minimal Containerfile lives at [image/Containerfile.minimal](../../../image/Containerfile.minimal) (user's chosen placement rather than `test/e2e/Containerfile`). It is selected by the Option 1 mechanism: `mk_talkbox` overwrites the temp talkbox copy's `image/Containerfile` with the repository's `image/Containerfile.minimal` after copying the tree, so every test-reachable build path — `ensure_base_image`, the three `--rebuild` build sites in [lib/containers.sh](../../../lib/containers.sh) — builds the minimal image from the temp root, whose `image/` context still contains `setup.sh`. `ensure_base_image_e2e` keeps building from `$talkbox/image/Containerfile` unchanged and picks up the minimal file automatically.

The swap mechanism is retained (rather than only building the file directly via an explicit `-f`) because otherwise the e2e `--rebuild` tests, which build unconditionally from `$TALKBOX_ROOT/image/Containerfile`, would still build the heavy production image — defeating the purpose of the minimal test image.
