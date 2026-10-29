# Verdict: the `podman()` unit mock swallows the probe's not-found exit, making the missing-HEAD `run_merge` test unpassable

Linked dispute: [gitdir-history-probe-not-found-exit-swallowed.gen.md](../disputes/gitdir-history-probe-not-found-exit-swallowed.gen.md)

Linked plan: [gitdir-history-podman-probe.gen.md](../plans/gitdir-history-podman-probe.gen.md) — summarised in one sentence: the plan replaces the host-side `podman volume inspect` mountpoint stat in `require_git_history` with a no-network `podman run` HEAD probe (`gitdir_probe_cmd`) interpreted three ways (0 = present, 1 = missing history, other = infra failure with surfaced stderr). No new issue documents were created: the defect was located entirely in the test helper, the core implementation was independently validated as correct, and no core-file issue remains outstanding.

## Test helper: the file-scope `podman()` mock (with `mock_container_run`)

- Helper: `podman()` (`"run "*` branch delegating to `mock_container_run`)
- File: [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) (formerly lines 211–233)
- Verdict: `BROKEN_HELPER`

### Justification

The plan requires the mock's `run` handler to:

> "extend the `podman` mock's `run` handler to recognise the probe invocation and resolve the volume's `HEAD` through the existing `PODMAN_MOUNTPOINTS` map"

and the [test-suite document](../tests/gitdir-history-podman-probe.gen.md) pins the fixture contract as:

> "`mock_container_run` recognises the probe invocation (consecutive `test -e /gitdir/HEAD` tokens) and resolves the volume's `HEAD` through the existing `PODMAN_MOUNTPOINTS` map, **returning the probe's not-found exit (1) when `HEAD` is absent in the mapped path**"

`mock_container_run` implements this correctly (its probe branch is `[[ -n "$repo" && -e "$repo/HEAD" ]]`, exiting 1 for an absent HEAD), but the wrapper discards the result: after the `"run "*` branch runs `mock_container_run "$@"`, the unconditional trailing `return 0` overwrites the branch's exit status, so `podman()` returns 0 for every `podman run` invocation. The probe's not-found exit therefore never reaches `require_git_history`, and the plan's three-way interpretation ("probe exit 0 → history present; the probe's not-found exit (1) → the existing `no git history in the $container gitdir volume; start the container first` message") is unobservable through this helper. Empirical confirmation (replicating the fixture verbatim outside bats): `mock_container_run run … test -e /gitdir/HEAD` with `PODMAN_MOUNTPOINTS` mapped to a directory without `HEAD` exits 1, while the same invocation through `podman()` exits 0.

### Repair

Minimal single-line repair: the unconditional `return 0` after the `case` statement was removed so the `"run "*` branch's own status (`mock_container_run`'s exit status, including the probe's not-found exit 1) flows out of `podman()`. No other behaviour changes: the `"volume exists"` branch already exits via explicit `return`s, the `PODMAN_FAIL_PATTERN` path returns before the `case`, and an unmatched `case` still yields status 0. The pass paths of the previously passing tests are unaffected (the probe-with-HEAD and `git bundle create` branches return 0; the bundle-failure tests exit through the `PODMAN_FAIL_PATTERN` branch before the removed statement).

## Test: `run_merge dies with the start the container first message when the gitdir volume has no HEAD`

- Test: `run_merge dies with the start the container first message when the gitdir volume has no HEAD`
- File: [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) (lines 339–354)
- Verdict: `BROKEN_IMPLEMENTATION`

### Justification

The test body is consistent with the plan and the test suite is aligned with the plan's red/green contract; its message assertion mirrors the plan's mandated interpretation:

> "probe exit 0 → history present; the probe's not-found exit (1) → the existing `no git history in the $container gitdir volume; start the container first` message"

with the added plan-required observations "no host-side mountpoint use" (`volume inspect` absence) and the probe invocation in the podman log. The test was unpassable for any conforming implementation solely because of the `BROKEN_HELPER` defect above: the swallowed probe exit made `require_git_history` fall through to the bundle fetch, so the test observed raw git `fatal:` output instead of the missing-history message. The core implementation is correct and required no change: the same not-found path passes against real podman in the e2e suite (`onbox merge on an uninitialised gitdir volume errors with a talkbox message`).

### Repair

None — the test is correct and is left unchanged. After the helper repair it passes against the unmodified implementation.

## Verification

- `make lint` passes and `shfmt --diff test/unit/git-transport.bats` is clean.
- `make test-unit`: `total=309 pass=309 fail=0 skip=0 exit=0` (the disputed test, unit test 85, passes).
- `make test-e2e`: `total=81 pass=81 fail=0 skip=0 exit=0` (including e2e test 39 exercising the probe's not-found path against real podman).
- Every remaining failure (none) is attributable to the project implementation rather than to a test error or timeout.
