# Dispute: the `podman()` unit mock swallows the probe's not-found exit, making the missing-HEAD `run_merge` test unpassable

Linked plan: [gitdir-history-podman-probe.gen.md](../plans/gitdir-history-podman-probe.gen.md) — summarised in one sentence: the plan replaces the host-side `podman volume inspect` mountpoint stat in `require_git_history` with a no-network `podman run` HEAD probe (`gitdir_probe_cmd`) and interprets the probe outcome three ways (0 = present, 1 = missing history, other = infra failure with surfaced stderr).

Related test-suite document: [gitdir-history-podman-probe.gen.md](../tests/gitdir-history-podman-probe.gen.md) (the red/green fixture contract referenced below).

Related core files: [lib/git.sh](../../../lib/git.sh) (`gitdir_probe_cmd`, `require_git_history`).

Status: `BLOCKED` on this dispute — the implementation is complete and passes 308/309 unit tests and 81/81 e2e tests; the single failing test cannot pass for any conforming implementation because of the helper defect described here.

## Disputed test helper: the file-scope `podman()` mock

- Helper: `podman()` (with `mock_container_run`)
- File: [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) (lines 211–233; the `"run "*` branch at lines 228–230 and the trailing `return 0` at line 232)

### Error

The plan requires the mock's `run` handler to "recognise the probe invocation and resolve the volume's `HEAD` through the existing `PODMAN_MOUNTPOINTS` map", and the tests document pins the fixture contract as "`mock_container_run` … returning the probe's not-found exit (1) when `HEAD` is absent in the mapped path". `mock_container_run` does implement this (its probe branch is `[[ -n "$repo" && -e "$repo/HEAD" ]]`, returning 1 for an absent HEAD), but the wrapper discards the result:

```bash
"run "*)
    mock_container_run "$@"
    ;;
esac
return 0
```

The unconditional trailing `return 0` overwrites the case's status, so `podman()` returns 0 for every `podman run` invocation regardless of what `mock_container_run` determined. The probe's not-found exit can therefore never reach `require_git_history`, and the three-way exit-code interpretation mandated by the plan (1 → the existing "no git history in the <container> gitdir volume; start the container first" message) is unobservable in the unit suite.

Empirical evidence, running the fixture verbatim outside bats:

- `mock_container_run run --rm … -v proj.onbox.gitdir:/gitdir:ro talkbox/base:latest test -e /gitdir/HEAD` with `PODMAN_MOUNTPOINTS[proj.onbox.gitdir]` mapped to a directory without `HEAD` → exit status **1**.
- The same invocation through `podman()` → exit status **0**.

No implementation of `require_git_history` can distinguish the absent-HEAD case through this helper: the probe's exit status is always 0, its stdout/stderr are empty, and the only other information (the mountpoint map) is test-internal. A conforming implementation then falls through to the bundle fetch, whose mocked `git bundle create` failure is swallowed the same way and whose host-side `git fetch` on the never-created bundle file fails with raw git `fatal:` output — exactly the conflation of transport failure with diagnostics the plan exists to remove.

### Repair (minimal, test-only)

Propagate `mock_container_run`'s status in the `"run "*` branch, e.g. replace the branch body and trailing `return 0` so the case's own status flows out (`mock_container_run "$@"` with the trailing `return 0` removed — the `"volume exists"` branch already exits via explicit `return`s and an unmatched case returns 0). The test body itself needs no change: with the helper fixed, the probe returns 1, `require_git_history` dies with the required message, and all assertions pass. No currently passing test depends on the swallowing behaviour: the bundle pass path (tests 82, 87) ends in a successful `git bundle create` inside the mock (status 0), and the bundle-failure tests (83, 88) exit early through the `PODMAN_FAIL_PATTERN` branch before the trailing `return 0`.

## Disputed test: `run_merge dies with the start the container first message when the gitdir volume has no HEAD`

- Test: `run_merge dies with the start the container first message when the gitdir volume has no HEAD`
- File: [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) (lines 339–354)

### Exact failure output (`make test-unit`)

```
not ok 85 run_merge dies with the start the container first message when the gitdir volume has no HEAD
# (in test file test/unit/git-transport.bats, line 350)
#   `[[ "$output" == *'talkbox: no git history in the onbox gitdir volume; start the container first'* ]]' failed
```

The `$output` the test actually captured (replicated out-of-band with the identical fixture and the implemented `lib/git.sh`, status 1):

```
fatal: Need a repository to create a bundle.
fatal: '/tmp/talkbox-merge.fMoPF6/onbox.bundle' does not appear to be a git repository
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

The podman log for the same run shows the probe was invoked and resolved as intended by the implementation — `run --rm --network=none --userns=keep-id:uid=1000,gid=1000 -v work.onbox.gitdir:/gitdir:ro talkbox/base:latest test -e /gitdir/HEAD` — with no `volume inspect` invocation, so the test's probe-log assertions (lines 352–353) pass; only the message assertion (line 350) is unpassable, and only because of the helper defect above.

### Justification

The test body is consistent with the plan and SPEC.md; its failure is caused solely by the disputed helper. The implementation passes every other probe-related test — the infra-failure diagnostic (test 86, which observes the surfaced podman stderr), the probe pass path before the bundle fetch (tests 87–88), and the real-podman e2e equivalents (`onbox merge on an uninitialised gitdir volume errors with a talkbox message`, e2e test 39, exercising the probe's not-found path against real podman, plus the whole 81-test e2e suite). Once the helper propagates `mock_container_run`'s exit status, this test is expected to pass unchanged against the current implementation.
