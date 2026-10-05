# Phase 20c: shared git bundle lifecycle and git-history probe in lib/git.sh

#flow/refactor #model/default

## scope

Resolves duplication item §7 (bundle tmp-dir lifecycle, `plan_fetch` execution tail, and the git-history guard duplicated between `run_fetch` and `require_git_history`) of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md).

- Implemented:
  - a shared internal helper owning the `mktemp -d` bundle-directory lifecycle — creating the temp dir, executing the two `plan_fetch` command arrays (bundle command, then host fetch) in order, and removing the temp dir on every exit path — used by both `run_fetch` (per container) and `run_merge`;
  - a shared gitdir-volume probe with fatal and non-fatal modes carrying the single copy of the `no git history for <container>; create the container first` guard, per the [run-fetch-git-history-probe choice](../../choices/run-fetch-git-history-probe.gen.md): `run_fetch` uses the non-fatal mode (preserving its `fetch --all` skip semantics and its volume-existence-only failure condition) and `require_git_history` builds on the fatal mode while keeping its additional mountpoint/`HEAD` check.
- Deferred: nothing else in [lib/git.sh](../../../lib/git.sh).

No aspect of `SPEC.md` changes; this refactors the "fetch" and "merge" implementations. External-facing behaviour is unchanged: same error messages, same `fetch --all` skip behaviour, same exit statuses, same ordering of git/podman operations.

## files to be created

None. Modified: [lib/git.sh](../../../lib/git.sh). Update its [MAP.gen.md](../../../MAP.gen.md) description if warranted.

## relevant files to be read

- [lib/git.sh](../../../lib/git.sh)
- [test/unit/git.bats](../../../test/unit/git.bats), [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) (behaviour-pinning tests)

## key internal interfaces

- New shared bundle-fetch helper (internal to [lib/git.sh](../../../lib/git.sh)) encapsulating the tmp-dir lifecycle and the two-command execution; `run_fetch` and `run_merge` call it.
- New shared gitdir-volume probe with fatal/non-fatal modes; `run_fetch` and `require_git_history` both route through it.
- Unchanged public surface: `plan_fetch`, `gitdir_bundle_cmd`, `host_fetch_cmd`, `run_fetch`, `run_merge`, `run_sync`, `require_git_history` keep their current signatures and semantics.

## tests

Unit tests required, including checks that podman commands are constructed correctly: the existing `plan_fetch` tests in [test/unit/git.bats](../../../test/unit/git.bats) and [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) pin the exact no-network `podman run` bundle command and host `git fetch` arrays and must keep passing unchanged. The pinning pass should add behaviour-level coverage for the currently untested `run_fetch` and `run_merge` paths — in particular: `fetch` failing with the `no git history` message when the gitdir volume is absent, `fetch --all` skipping containers with missing volumes, bundle-command failure surfacing as a non-zero result, and the temp-dir cleanup. No existing tests are superseded or removed.
