# Tests: Phase 5 git merge and sync

Linked plan: [phase-5-merge-sync.gen.md](../plans/phase-5-merge-sync.gen.md)

Summary: this phase adds failing tests for the Phase 5 features — the `custom_merge()` merge logic (DESCENDANT_CHECK, current-branch Cases 1-3 and the other-branch `git branch -f` fast-forward), the `merge` subcommand (fetch from the container gitdir volume then `custom_merge <container> <branch>` on the host, with the host's current branch as the default, a `<branchname>` positional and `--all`), and the `sync` subcommand (fetch from the `host` remote and `custom_merge host <branch>` inside the container's repository). This completes `SPEC.md`'s git-as-transport section.

The tests pin the following interfaces, which the implementation must provide so that the tests pass once the plan is implemented:

- `lib/git.sh`: `custom_merge <remote> <branchname>` — location-agnostic plain-`git` merge logic run from the current working directory, with the pure precondition checks (branch existence, DESCENDANT_CHECK descendant-of, clean-worktree detection) unit-testable against a fixture repository; only `git merge --ff-only` / `git reset --mixed` / `git branch -f` / a warning mutate state.
- `lib/options.sh`: `parse_onbox_options` recognises the bare positionals `merge` and `sync` as verbs (field `ONBOX_VERB`) while `-c merge`/`-c sync` remain commands, and exposes the optional `<branchname>` positional (field `ONBOX_BRANCH`) alongside the existing `--all` flag (field `ONBOX_ALL`).
- `talkbox.sh` routing plus `lib/git.sh`/`lib/containers.sh`: `onbox|netbox|offbox merge [<branchname>] [--all]` fetches from the corresponding gitdir volume and applies `custom_merge <container> <branch>` in the host repository; `onbox|netbox|offbox sync [<branchname>] [--all]` runs git inside the container's repository (`podman exec` on a running persistent container, or a temporary no-network container mounting the gitdir volume, worktree and `/host/git` otherwise), fetching from the `host` remote and applying `custom_merge host <branch>`.

## New tests

Unit tests (`test/unit/merge.bats`, 7 tests) — each builds a fixture repository pair (a bare `origin.git` and a worktree `work` with an initial commit pushed to origin) in `BATS_TEST_TMPDIR`, then runs `custom_merge` against `work`:

- `custom_merge fast-forwards a clean current branch (Case 1)` - with `refs/remotes/origin/<branch>` a descendant of the clean current branch, HEAD, the branch ref and the worktree file all advance to the remote commit.
- `custom_merge updates the branch when the worktree already matches the remote (Case 2)` - with an unstaged worktree whose content already equals the remote commit, the branch ref is advanced to the remote commit while the worktree is left unchanged (the `git reset --mixed` path).
- `custom_merge leaves a dirty worktree untouched and warns (Case 3)` - with a worktree modified to match neither HEAD nor the remote, HEAD and the worktree are unchanged and a `talkbox:` warning is emitted.
- `custom_merge warns and makes no change when the remote branch is not a descendant` - a locally-ahead branch whose remote-tracking ref is an ancestor fails DESCENDANT_CHECK and changes nothing, with a `talkbox:` warning.
- `custom_merge warns and makes no change when the remote-tracking branch is absent` - an existing local branch with no `refs/remotes/<remote>/<branch>` fails DESCENDANT_CHECK, leaving the branch and the current checkout untouched and emitting a `talkbox:` warning.
- `custom_merge creates a new branch without switching when the branch does not exist` - with no local branch but a descendant remote branch, `git branch -f` creates the branch at the remote commit while the current checkout and HEAD are unchanged.
- `custom_merge advances an existing non-current branch without switching` - an existing non-current local branch behind its descendant remote branch is advanced via `git branch -f` while the current checkout and HEAD are unchanged.

These pin the plan's "`custom_merge()` DESCENDANT_CHECK outcomes for all branch-existence/descendant combinations; Case 1 ...; Case 2 ...; Case 3 ...; other-branch `git branch -f` advance without switching", together with [SPEC.md §`custom_merge()`](../../../SPEC.md) (DESCENDANT_CHECK, Cases 1-3, other-branch).

Unit tests (`test/unit/options.bats`, 5 tests added):

- `onbox merge is parsed as the merge verb while -c merge remains a command` - bare `merge` sets `ONBOX_VERB=merge` with no command, while `-c merge` keeps `ONBOX_COMMAND=merge`.
- `onbox merge <branchname> records the merge verb and the branch positional` - `ONBOX_VERB=merge` and `ONBOX_BRANCH=<branchname>` with no command.
- `onbox merge --all sets the merge verb and the --all flag` - `ONBOX_VERB=merge` and `ONBOX_ALL=yes` with no command.
- `onbox sync is parsed as the sync verb while -c sync remains a command` - bare `sync` sets `ONBOX_VERB=sync` with no command, while `-c sync` keeps `ONBOX_COMMAND=sync`.
- `onbox sync <branchname> --all records the sync verb, branch and --all flag` - `ONBOX_VERB=sync`, `ONBOX_BRANCH=<branchname>` and `ONBOX_ALL=yes` with no command.

These pin the plan's "parse the `merge`/`sync` subcommand verbs, their `--all` flag and optional `<branchname>`" and "the `merge`/`sync` verb, `--all` flag and `<branchname>` positional are exposed in the parsed record".

End-to-end tests (`test/e2e/merge-sync.bats`, 6 tests), run under the existing `systemd-run`-wrapped runner on a temporary git project with a tracked file:

- `onbox fetch then onbox merge brings a container commit into the host worktree` - after an in-container empty commit, `onbox fetch` + `onbox merge` fast-forwards the clean host branch so `git log` shows the container commit.
- `onbox merge <branchname> merges the named branch without switching` - an in-container commit on `feature` is brought into the host `feature` branch via `onbox merge feature`, while the host's current branch is unchanged (the other-branch `git branch -f` path).
- `onbox merge --all applies custom_merge across all onbox branches` - with commits on the current branch and on `feature` in the container, `onbox merge --all` fast-forwards the current branch and creates/advances `feature` on the host.
- `onbox merge leaves a dirty host worktree untouched and warns` - with the host worktree modified after `onbox fetch`, `onbox merge` leaves HEAD and the modified file untouched and emits a `talkbox:` warning.
- `onbox merge refuses a non-descendant with a warning and leaves HEAD unchanged` - with a host commit diverging from a container commit, `onbox merge` leaves HEAD and the clean worktree unchanged and emits a `talkbox:` warning.
- `onbox sync brings a host commit into the onbox gitdir volume` - after a host commit, `onbox sync` advances the onbox gitdir volume's `refs/heads/<branch>` to the host HEAD and the container's `git log` shows the host commit.

These pin the plan's "commit inside `onbox`, then `onbox fetch` + `onbox merge` brings the commit into the host repo via a bundle (host worktree fast-forwards when clean); host commit followed by `onbox sync` brings it into the onbox gitdir volume; `--all` operates across branches; a dirty host worktree leaves it untouched and warns; merge of a non-descendant is refused with a warning", together with [SPEC.md §merge](../../../SPEC.md) and [SPEC.md §sync](../../../SPEC.md).

## Tests edited

- `test/unit/options.bats` - `setup()` now also initialises the new record field `ONBOX_BRANCH` (empty). Evidence from the plan: "the `merge`/`sync` verb, `--all` flag and `<branchname>` positional are exposed in the parsed record" — the field is initialized alongside the existing `ONBOX_VERB`/`ONBOX_ALL`/`ONBOX_COMMAND` fields so each `parse_onbox_options` invocation starts clean. No existing assertion was changed.

No other existing tests were edited: the `custom_merge()` behaviour is entirely new, and the merge/sync action flows (the plan's unit bullet for "merge/sync action plan assembly") are pinned through the option-parsing unit tests above plus the end-to-end flows, rather than through internal action-plan function names, which the plan does not specify — pinning guessed names would over-constrain the implementation.

## Tests removed

None. All pre-existing tests remain consistent with the plan: they pin container assembly, mounts, lifecycle verbs and the `fetch` transport, none of which the Phase 5 changes alter, and the plan's "Deferred: Nothing remains of `SPEC.md` after this phase" introduces no behaviour change to existing tests. [SPEC.md §git as transport](../../../SPEC.md) defines `custom_merge()`/`merge`/`sync` as additions over the Phase-4 `fetch`, which no pre-existing test exercises.
