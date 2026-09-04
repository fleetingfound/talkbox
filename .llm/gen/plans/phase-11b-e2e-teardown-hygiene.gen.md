# Plan: Phase 11b — E2e test teardown hygiene

#flow/pin #model/default

## Specification scope

No aspect of `SPEC.md` / `SPEC.gen.md` is altered. This addresses the test-state
pollution dimension of the issue [E2e commands executed on a freshly started
container race the entrypoint](../issues/e2e-fresh-container-exec-races-entrypoint.gen.md):
the `test/e2e/onbox.bats` teardown leaks `<slug>.onbox.gitdir` named volumes
and only removes the onbox container, leaving netbox/offbox containers and
root images behind when tests fail mid-way. This state pollution causes
`netbox --rm-image` to trip the `image_in_use` guard (leftover containers
reference the base image) and widens the entrypoint race (accumulated leftover
containers and volumes slow podman).

## To be implemented

- In [test/e2e/helpers.bash](../../../test/e2e/helpers.bash), add a shared
  teardown helper function (e.g. `teardown_talkbox <slug> [extra-container...]`)
  that performs the full cleanup sequence already duplicated across
  `lifecycle.bats`, `netbox-offbox.bats`, `git-identity.bats`,
  `git-transport.bats` and `merge-sync.bats`:
  1. `podman rm -f -v` all three canonical containers (`<slug>.onbox`,
     `<slug>.netbox`, `<slug>.offbox`) plus any extra containers passed as
     additional arguments.
  2. `podman rmi` the netbox and offbox root images
     (`<slug>.netbox.root`, `<slug>.offbox.root`).
  3. Remove all named volumes matching `<slug>` via `podman volume ls --filter`
     and `podman volume rm -f`.
- Update [test/e2e/onbox.bats](../../../test/e2e/onbox.bats) `teardown()` to
  call the shared helper instead of only removing the onbox container. The
  current onbox.bats teardown is the sole source of the named-volume leak: it
  does `podman rm -f -v "$CTR"` (which removes only anonymous volumes, not the
  separately-created named gitdir volume) and does not clean up netbox/offbox
  containers or root images that may have been created by a partially-failed
  test.
- Update the teardown functions in `lifecycle.bats`, `netbox-offbox.bats`,
  `git-identity.bats`, `git-transport.bats` and `merge-sync.bats` to call the
  shared helper, replacing the duplicated inline cleanup sequences. Each test
  file's teardown may pass extra containers (e.g. `PLAIN_CTR` in
  `git-transport.bats` and `merge-sync.bats`) and extra directories to clean
  up.
- The shared helper should tolerate the absence of any container, volume or
  image (all removals use `|| true` or `--force`), matching the current
  behaviour of the inline teardowns.

## To be deferred

- Adding a `setup`-level pre-flight that removes any leftover state from a
  previous run before the test begins. The improved teardown should be
  sufficient; a pre-flight would add complexity and slow tests.
- Refactoring the `EXTRA_DIRS` cleanup pattern into the shared helper. The
  extra-directories cleanup is host-side `rm -rf` and is simple enough to
  leave inline in the few test files that use it.

## External-facing functionality

None. This is a test-only change with no impact on the talkbox implementation.
The e2e suite becomes more robust against state pollution from failed or
interrupted test runs, eliminating the intermittent `image_in_use` guard
failures and reducing the container/volume accumulation that widens the
entrypoint race.

## Files to be created

- None.

## Files to read during implementation

- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — add the shared
  teardown helper alongside the existing `sdrun`, `mk_project`, `mk_talkbox`
  helpers.
- [test/e2e/onbox.bats](../../../test/e2e/onbox.bats) — replace the minimal
  `teardown()` with a call to the shared helper.
- [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) — replace the
  inline cleanup with the shared helper (note: this file also kills
  `HOST_SRV_PID`; that remains inline).
- [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) — replace
  the inline cleanup with the shared helper.
- [test/e2e/git-identity.bats](../../../test/e2e/git-identity.bats) — replace
  the inline cleanup with the shared helper.
- [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats) — replace
  the inline cleanup with the shared helper (note: passes `PLAIN_CTR` as an
  extra container and cleans `EXTRA_DIRS`).
- [test/e2e/merge-sync.bats](../../../test/e2e/merge-sync.bats) — replace the
  inline cleanup with the shared helper (same extra-container/dirs pattern as
  git-transport).

## Key internal interfaces

- A new shared teardown helper in `test/e2e/helpers.bash` (e.g.
  `teardown_talkbox <slug> [extra-container...]`) that performs the canonical
  container/image/volume cleanup. No return value; all operations are
  best-effort with `|| true`.

## Tests

This phase is itself a test modification. No additional tests are required
beyond verifying that the full e2e suite continues to pass 67/67 with the
refactored teardowns. The key validation is running the suite multiple times
in succession (or with deliberately injected mid-test failures) and confirming
no state leaks between runs.
