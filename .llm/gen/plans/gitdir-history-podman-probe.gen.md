# Podman-backed gitdir history probe in `require_git_history`

#flow/redgreen #model/default

## Scope

Resolves the issue [onbox merge fails the git-history probe on machines where the podman volume mountpoint is not host-visible](../../issues/onbox-merge-gitdir-volume-host-path-check.gen.md) and the review [onbox-merge-git-history-probe investigation](../../reviews/onbox-merge-git-history-probe.gen.md).

Implements the selected choices [gitdir history probe mechanism](../choices/gitdir-history-probe-mechanism.gen.md) (podman-run volume-mounted HEAD probe) and [gitdir probe failure diagnostics](../choices/gitdir-probe-failure-diagnostics.gen.md) (three-way exit-code interpretation with surfaced stderr).

### Aspects implemented

- `SPEC.md` "git as transport" → `merge`/`sync` step 1 for all three containers: the pre-merge/pre-sync git-history guard must succeed on every podman configuration (local rootless, rootful/system-service, remote/machine), not only where the volume mountpoint is host-visible.
- `require_git_history` in `lib/git.sh`: replace the host-side `podman volume inspect` mountpoint stat with a no-network `podman run` probe that mounts the gitdir volume read-only at `/gitdir` and tests for `HEAD` inside the container, mirroring the `gitdir_bundle_cmd` pattern (`plan_no_net_run` prefix, `gitdir_volume` mount, base image).
- Three-way outcome interpretation: probe exit 0 → history present; the probe's not-found exit (1) → the existing `no git history in the $container gitdir volume; start the container first` message; any other exit status or `podman run` failure → a distinct `talkbox:` diagnostic that surfaces the podman stderr, so transport/infrastructure failures are no longer conflated with missing history (the `2>/dev/null` conflation defect).
- The volume-exists guard (`require_gitdir_volume`) and the `git_tracked` guard are unchanged.

### Aspects deferred

- No changes to `run_fetch` (it has no history guard by design, per the [run-fetch git-history probe choice](../choices/run-fetch-git-history-probe.gen.md)), `gitdir_volume_exists` or `run_sync`/`run_merge` control flow.
- No new host-side `podman volume inspect` usage anywhere; the e2e `volume_mountpoint` helper remains test-only fixture code.
- No changes to the bundle fetch, sync-in-container or `custom_merge` behaviour.

## Files to create

- none (all changes are to existing files)

## Files to modify

- `lib/git.sh` — new probe-command planner (populating a `podman run` array in the `gitdir_bundle_cmd` style: `plan_no_net_run` prefix, `<gitdir-volume>:/gitdir:ro` mount, base image, `test -e /gitdir/HEAD`) and `require_git_history` rewritten to execute it and interpret the three exit outcomes, capturing stderr for the infra-failure message.
- `test/unit/git-transport.bats` — extend the `podman` mock's `run` handler to recognise the probe invocation and resolve the volume's `HEAD` through the existing `PODMAN_MOUNTPOINTS` map; rewrite the mountpoint-based tests; keep the `PODMAN_FAIL_PATTERN` mechanism for the infra-failure case.
- `test/unit/git.bats` — add a planner unit test asserting the exact probe command structure (prefix, mount, image, probe command) alongside the existing `gitdir_bundle_cmd` structure test.
- `MAP.gen.md` — update the `lib/git.sh` entry (the probe is no longer a mountpoint stat).

## Key interfaces

- New planner in `lib/git.sh` (alongside `gitdir_bundle_cmd`): assembles the probe command array from the project, container and gitdir volume name; `require_git_history` executes it and maps the exit status: `1` → missing history (existing message), other non-zero → infra failure diagnostic including the captured podman stderr.
- The existing `require_git_history` call sites (`run_merge`, `run_sync`) and its error-message contract for the missing-history case are unchanged.

## Tests

Requires tests.

- Unit tests (`test/unit/git-transport.bats`, `test/unit/git.bats`):
  - the exact probe command structure (planner array contents);
  - `run_merge`/`run_merge`-level: history present → merge proceeds; `HEAD` absent in the volume → `no git history in the <container> gitdir volume; start the container first` with no host-side mountpoint use; podman-run failure (non-1 exit) → distinct infra diagnostic that includes the podman stderr; volume absent → existing `no git history for <container>; create the container first` message unchanged.
- End-to-end tests (`test/e2e/merge-sync.bats`): the existing `onbox merge on an uninitialised gitdir volume errors with a talkbox message` test exercises the real podman probe against a volume created without `HEAD`; the remaining merge/sync e2e tests exercise the pass path of the probe with real podman. No new e2e tests are required.

### Tests to be superseded

- The `run_merge dies with the start the container first message when the gitdir volume has no HEAD` test's fixture (`PODMAN_MOUNTPOINTS` empty mountpoint + `volume inspect` mocking) is replaced by a probe-driven fixture where the mocked `podman run` reports the volume's `HEAD` as absent; the `volume inspect` branch of the unit `podman` mock is removed together with the production `volume inspect` call.
