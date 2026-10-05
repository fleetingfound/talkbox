# Phase 20c: shared git bundle lifecycle and git-history probe in lib/git.sh

Pinning-test pass for [phase-20c-git-bundle-lifecycle](../plans/phase-20c-git-bundle-lifecycle.gen.md), which refactors `lib/git.sh` so a shared bundle-fetch helper owns the tmp-dir lifecycle and a shared fatal/non-fatal gitdir-volume probe carries the `no git history` guard, with no external behaviour change. These tests pin the current `run_fetch`/`run_merge` behaviour so the refactor can proceed safely; no core files were modified.

## New tests (test/unit/git-transport.bats)

All new tests use a function-based `podman()` mock (added to the same file) that logs invocations, emulates `volume exists`/`volume inspect --format '{{.Mountpoint}}'` via `PODMAN_VOLUMES` and a `PODMAN_MOUNTPOINTS` map, optionally fails matching invocations via `PODMAN_FAIL_PATTERN`, and, on `podman run`, creates a real git bundle from a stand-in container gitdir (a clone of the fixture repo with one extra empty commit).

1. `run_fetch dies with the no git history message when the gitdir volume is absent` — single-container fetch with no existing volume exits non-zero with `talkbox: no git history for onbox; create the container first` and leaves no `talkbox-fetch.*` temp directory behind (TMPDIR scan).
2. `run_fetch --all skips every container with a missing gitdir volume` — with all three gitdir volumes absent, `fetch --all` returns 0 and creates no `refs/remotes/{onbox,netbox,offbox}/*` refs.
3. `run_fetch --all fetches only from containers whose gitdir volume exists` — with only the onbox volume present, `fetch --all` brings the container commit into `refs/remotes/onbox/<branch>` (and nothing for netbox/offbox), and the bundle temp directory revealed in the podman log (`-v <dir>:/host/bundle`) is removed afterwards.
4. `run_fetch surfaces a failed bundle command as a non-zero result without fetching` — a failing `podman run` bundle command makes `run_fetch` return non-zero, no `refs/remotes/onbox/*` refs are created, and the temp directory (extracted from the log) is cleaned up.
5. `run_merge dies with the no git history message when the gitdir volume is absent` — pins the fatal mode of the git-history probe via `run_merge`.
6. `run_merge dies with the start the container first message when the gitdir volume has no HEAD` — volume exists but its mountpoint lacks `HEAD`; `run_merge` exits non-zero with `talkbox: no git history in the onbox gitdir volume; start the container first` and does not move the host HEAD.
7. `run_merge fetches the container bundle and fast-forwards the current branch` — full success path: bundle is created in the mock container, fetched into `refs/remotes/onbox/<branch>`, and `custom_merge` fast-forwards the host HEAD to the container commit; the `talkbox-merge.*` temp directory is removed.
8. `run_merge surfaces a failed bundle command as a non-zero result without merging` — bundle-command failure makes `run_merge` return non-zero with HEAD unchanged and the temp directory cleaned up.

## Edited tests

None. The existing `plan_fetch` tests in `test/unit/git.bats` and `test/unit/git-transport.bats` pass unchanged, as required by the plan.

## Removed tests

None. The plan states that no existing tests are superseded or removed.

## Results

`make test-unit`: 266 passed / 0 failed (8 new). `make test-e2e`: 76 passed / 0 failed. `make lint` (shellcheck) and `shfmt -d` clean.
