# Phase 5: git merge and sync

#flow/redgreen #model/default

## Scope

Implements the remaining git-transport subcommands that move committed changes between the host repository and the per-container gitdir volumes: the `custom_merge()` merge logic, and the `merge` and `sync` subcommands. Completes `SPEC.md`.

### Implemented from SPEC.md

- `custom_merge()` shell function implementing DESCENDANT_CHECK and the current-branch (Cases 1-3) and other-branch (`git branch -f`) behaviours.
- `onbox merge` / `netbox merge` / `offbox merge` apply `custom_merge <container> <branch>` after fetching from the corresponding gitdir volume; default branch = host's current branch; `<branchname>` positional; `--all` over all container branches.
- `onbox sync` / `netbox sync` / `offbox sync` run inside the container's git repository to fetch from the `host` remote and apply `custom_merge host <branch>`; default branch = host's current branch; `<branchname>` positional; `--all` over all host branches.
- All merges are fast-forward only; no working-tree changes except when fast-forwarding a branch with no staged changes and a clean worktree.

### Deferred

- Nothing remains of `SPEC.md` after this phase.

## External-facing functionality

- `onbox|netbox|offbox merge [<branchname>] [--all]`
- `onbox|netbox|offbox sync [<branchname>] [--all]`

## Files to create / modify

- Modify `lib/git.sh` - implement `custom_merge()` (DESCENDANT_CHECK, current-branch Cases 1-3, other-branch fast-forward), the `merge` action (fetch from the gitdir volume then `custom_merge <container> <branch>`), and the `sync` action (run git inside the container's repository to fetch from the `host` remote then `custom_merge host <branch>`).
- Modify `lib/options.sh` - parse the `merge`/`sync` subcommand verbs, their `--all` flag and optional `<branchname>`.
- Modify `lib/containers.sh` - helper to run git inside a given container's git repository (via `podman exec` or a temporary container mounting the container's gitdir volume, with no network needed) for `sync`.
- Modify `talkbox.sh` - route `merge`/`sync` subcommands for each container.

## Files to read during implementation

- `SPEC.md` (git as transport, `custom_merge()`, merge, sync).
- `lib/git.sh` from Phase 4.
- `.llm/ref/podman.docs`.

## Key internal interfaces

- `lib/git.sh`:
  - `custom_merge <remote> <branchname>` - the merge logic, factored so its pure precondition checks (DESCENDANT_CHECK, clean-worktree detection, branch-existence, descendant-of) are individually unit-testable against a fixture git repository; only the final `git merge --ff-only` / `git reset --mixed` / `git branch -f` / warning emit execute `git`.
  - The `merge` action composes the Phase-4 `fetch` with `custom_merge <container> <branch>`.
  - The `sync` action runs its git commands inside the container's repository (via `podman exec` or a temporary container mounting the container's gitdir volume, with no network needed) then applies `custom_merge host <branch>`.
- `lib/options.sh`: the `merge`/`sync` verb, `--all` flag and `<branchname>` positional are exposed in the parsed record.

## Tests

- **Unit tests** (`test/unit/`): `custom_merge()` DESCENDANT_CHECK outcomes for all branch-existence/descendant combinations; Case 1 (clean worktree, ff-only merge updates HEAD/worktree); Case 2 (worktree already matches remote -> `git reset --mixed`); Case 3 (dirty worktree -> no change + warning); other-branch `git branch -f` advance without switching; merge/sync action plan assembly (which git subcommands run and against which repository/volume). These use a temporary fixture git repository created in `BATS_TEST_TMPDIR`.
- **End-to-end tests** (`test/e2e/`): commit inside `onbox`, then `onbox fetch` + `onbox merge` brings the commit into the host repo via a bundle (host worktree fast-forwards when clean); host commit followed by `onbox sync` brings it into the onbox gitdir volume; `--all` operates across branches; a dirty host worktree leaves it untouched and warns; merge of a non-descendant is refused with a warning. Run under the existing `systemd-run`-wrapped runner.
