# Choice: Minimal test image scoping

How the request to modify the test suite to use a minimal Containerfile should be scoped relative to the existing unimplemented [Phase 18 plan](../plans/phase-18-alternate-containerfile.gen.md), which bundles the test-suite adoption with the `--containerfile` CLI flag.

## Context

- [Phase 18](../plans/phase-18-alternate-containerfile.gen.md) (unimplemented) plans: the `--containerfile` flag, the `TALKBOX_CONTAINERFILE` and `TALKBOX_BASE_IMAGE` environment variables, `image/Containerfile.minimal`, and the `make test-unit` / `make test-e2e` defaults, per the recorded choices [alternate-containerfile-selection](alternate-containerfile-selection.gen.md) and [test-base-image-tag](test-base-image-tag.gen.md).
- The current request asks only for the test-suite modification, prompting the question of whether the CLI flag should be deferred, kept in the same phase, or dropped.
- A pure test-suite change cannot adopt the minimal Containerfile on its own: the base image tag and Containerfile path are hardcoded in `lib/naming.sh` and `lib/containers.sh`, and building the minimal image to the shared `talkbox/base:latest` tag would either clobber the developer's full image or be shadowed by it (the rejected option in [test-base-image-tag](test-base-image-tag.gen.md)). The narrowed scope therefore still needs the environment-variable mechanism, but not necessarily the flag.

## Options

### Option A: Split — new test-suite phase, flag deferred (Recommended)

- A new phase (18a) implements only the minimal Containerfile adoption: `image/Containerfile.minimal`, the `TALKBOX_CONTAINERFILE` / `TALKBOX_BASE_IMAGE` overrides in core code, and the `make test-unit` / `make test-e2e` harness defaults.
- Phase 18 is reduced to the `--containerfile` CLI flag and its tests, building on 18a's resolution helper.
- The recorded choices remain valid; the test-suite benefit lands without the CLI change; the two phases remain independently implementable, matching the repo's existing sub-phase convention (e.g. 14a–14c, 16a–16d).

### Option B: No split — keep full Phase 18

- The existing Phase 18 plan already covers the test-suite modification plus the flag in one phase; no new plan document is created and the request is satisfied by implementing Phase 18 as planned.

### Option C: Drop the flag

- Phase 18 is re-scoped to the environment-variable mechanism only; the `--containerfile` CLI flag is removed from the plan entirely, superseding the earlier user selection in [alternate-containerfile-selection](alternate-containerfile-selection.gen.md).
