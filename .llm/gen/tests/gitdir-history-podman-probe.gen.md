# Podman-backed gitdir history probe in `require_git_history`

Red/green test suite for [the plan](../plans/gitdir-history-podman-probe.gen.md), which replaces the host-side `podman volume inspect` mountpoint stat in `require_git_history` with a no-network `podman run` HEAD probe (mirroring `gitdir_bundle_cmd`) and interprets the probe outcome three ways (0 = present, 1 = missing history, other = infrastructure failure with surfaced stderr). The plan resolves [the gitdir-volume host-path-check issue](../issues/onbox-merge-gitdir-volume-host-path-check.gen.md); no new issue documents were created for this phase.

No core files were edited. Only [test/unit/git-transport.bats](../../../test/unit/git-transport.bats), [test/unit/git.bats](../../../test/unit/git.bats) and this document were changed. The plan also lists `MAP.gen.md` under "Files to modify"; that update describes the implemented state and is left to the implementation phase.

## New tests

All are in the unit suite (`make test-unit`). Each fails before implementation, for a plan-relevant reason, and passes once the plan is implemented.

### `test/unit/git.bats`

- **`gitdir_probe_cmd opens with the exact no-network run prefix, the read-only gitdir mount and the HEAD probe`** — pins the planner array contents token-by-token: the `plan_no_net_run` prefix (`podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000`), the single read-only mount `<project-slug>.<container>.gitdir:/gitdir:ro`, the base image (`$(base_image_name)`), and the probe command `test -e /gitdir/HEAD`, with a total length of 11 tokens. Implements the plan's test item "the exact probe command structure (planner array contents)":
  > "test/unit/git.bats — add a planner unit test asserting the exact probe command structure (prefix, mount, image, probe command) alongside the existing `gitdir_bundle_cmd` structure test."

  The planner is called with `(out-array, project, container)`; the plan names no function ("New planner in `lib/git.sh` (alongside `gitdir_bundle_cmd`)"), so the test fixes the name `gitdir_probe_cmd` as the contract, in parallel with `gitdir_bundle_cmd`. Fails pre-implementation with `gitdir_probe_cmd: command not found` (status 127).

### `test/unit/git-transport.bats`

- **`run_merge reports a distinct infra diagnostic with the podman stderr when the history probe run fails`** — with the gitdir volume present and its `HEAD` resolvable, `PODMAN_FAIL_PATTERN='test -e /gitdir/HEAD'` + `PODMAN_FAIL_CODE=125` makes the mocked probe invocation fail with a non-1, non-0 status and `PODMAN_FAIL_STDERR='podman: cannot connect to the podman socket'` on stderr. Asserts `run_merge` exits non-zero with a `talkbox:` diagnostic naming `onbox`, that the diagnostic is distinct from the missing-history message (`output != *'no git history in the onbox gitdir volume'*`), that the podman stderr text is surfaced, and that the host HEAD is untouched. Implements the plan's three-way interpretation:
  > "any other exit status or `podman run` failure → a distinct `talkbox:` diagnostic that surfaces the podman stderr, so transport/infrastructure failures are no longer conflated with missing history (the `2>/dev/null` conflation defect)."

  Fails pre-implementation because the current code still conflates the failure with the missing-history message (the `output !=` assertion trips).

### Mock support (new in the `test/unit/git-transport.bats` fixture)

- The file-scope `podman()` mock prints `PODMAN_FAIL_STDERR` to stderr before returning `PODMAN_FAIL_CODE` when `PODMAN_FAIL_PATTERN` matches, so the infra diagnostic's stderr-surfacing requirement is observable. `PODMAN_FAIL_PATTERN` matching is otherwise unchanged.
- `mock_container_run` recognises the probe invocation (consecutive `test -e /gitdir/HEAD` tokens) and resolves the volume's `HEAD` through the existing `PODMAN_MOUNTPOINTS` map, returning the probe's not-found exit (1) when `HEAD` is absent in the mapped path; the bundle-command handling is unchanged. Implements the plan's fixture requirement:
  > "extend the `podman` mock's `run` handler to recognise the probe invocation and resolve the volume's `HEAD` through the existing `PODMAN_MOUNTPOINTS` map; rewrite the mountpoint-based tests; keep the `PODMAN_FAIL_PATTERN` mechanism for the infra-failure case."

## Edited tests

All in [test/unit/git-transport.bats](../../../test/unit/git-transport.bats); no test bodies outside the fixture/observation points listed below were changed.

- **`run_merge dies with the start the container first message when the gitdir volume has no HEAD`** — the fixture is replaced: instead of the empty-mountpoint + `volume inspect` mocking, `PODMAN_MOUNTPOINTS[$VOL]` points at a directory without `HEAD` and the mocked `podman run` reports it as absent. The test keeps the message and HEAD-untouched assertions and adds two probe observations: the podman log contains a `test -e /gitdir/HEAD` probe invocation and contains no `volume inspect` invocation ("no host-side mountpoint use"). Justification — the plan explicitly supersedes this fixture and requires the mountpoint machinery to be gone:
  > "The `run_merge dies with the start the container first message when the gitdir volume has no HEAD` test's fixture (`PODMAN_MOUNTPOINTS` empty mountpoint + `volume inspect` mocking) is replaced by a probe-driven fixture where the mocked `podman run` reports the volume's `HEAD` as absent; the `volume inspect` branch of the unit `podman` mock is removed together with the production `volume inspect` call."

  and

  > "`require_git_history` in `lib/git.sh`: replace the host-side `podman volume inspect` mountpoint stat with a no-network `podman run` probe that mounts the gitdir volume read-only at `/gitdir` and tests for `HEAD` inside the container"

  Fails pre-implementation at the probe-log assertion (the production code still uses `volume inspect` and never runs the probe).

- **`run_merge fetches the container bundle and fast-forwards the current branch`** (body unchanged) — its fixture now resolves the volume contents through the probe branch of the mock (the `volume inspect` branch the old guard relied on is gone), so the test exercises the plan's "history present → merge proceeds" pass path of the probe before the bundle fetch. Justification — same plan excerpts as above; the plan's test list requires "run_merge/run_merge-level: history present → merge proceeds". Fails pre-implementation at `[[ "$status" -eq 0 ]]` because the removed `volume inspect` branch leaves the old guard with an empty mountpoint.

- **`run_merge surfaces a failed bundle command as a non-zero result without merging`** (body unchanged) — same fixture conversion; the `PODMAN_FAIL_PATTERN='bundle create'` failure is still isolated to the bundle command, so the probe's pass path is exercised first. Fails pre-implementation at the `talkbox-merge.*` temp-directory assertion for the same reason (the old guard dies before any bundle run).

## Removed tests

None. No existing test is inconsistent with the plan: the superseded fixture belongs to a test that was rewritten rather than removed, and every other existing unit test (including the four `run_fetch` tests, which keep `PODMAN_FAIL_PATTERN`/`PODMAN_MOUNTPOINTS` semantics and exercise no history guard, per the plan's deferred aspects) and e2e test remains valid. In particular the e2e suite is untouched — per the plan, "No new e2e tests are required": the existing `onbox merge on an uninitialised gitdir volume errors with a talkbox message` test exercises the real-podman probe against a volume created without `HEAD`, and the remaining merge/sync e2e tests exercise its pass path. The e2e `volume_mountpoint` helper stays as test-only fixture code.

## Observed red state (pre-implementation)

- `make test-unit`: 309 tests, 5 failures — exactly the two new tests and the three edited tests above, each at the plan-relevant assertion described above; no unrelated test regressed.
- `make test-e2e`: 81/81 pass.
