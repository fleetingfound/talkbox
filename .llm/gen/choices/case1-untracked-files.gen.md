# Choice: Case 1 untracked-files handling in `custom_merge_current`

Related review: [git-transport-review](../reviews/git-transport-review.gen.md) (observation 1)

## Context

[SPEC.md](../../SPEC.md) §"`custom_merge()`" Case 1 fires when "there are no staged changes and the worktree is clean relative to `HEAD`". The implementation in [lib/merge.sh](../../lib/merge.sh) uses `[[ -z "$(git status --porcelain)" ]]`, which is empty only when there are no staged changes, no unstaged tracked changes, **and** no untracked files.

A literal reading of "the worktree is clean relative to `HEAD`" could be interpreted as allowing untracked files, since untracked files are not part of the tree tracked by `HEAD`. The implementation is therefore stricter than a literal reading: an untracked file causes fall-through to Case 2 (`worktree_matches_tree`, which `git add -A`s the entire worktree including untracked files, so it also fails to match) and then to Case 3 (warn, no change).

This is safe — `git merge --ff-only` would not overwrite an untracked file that conflicts with a tracked file in the merge result — but a user with harmless untracked files (e.g. editor backup files, build artifacts in a `.gitignore`-excluded path) will be warned rather than fast-forwarded.

## Options

### Option A — Allow untracked files in Case 1 (Recommended)

Replace the `git status --porcelain` emptiness check with a two-part check that matches the spec's literal wording:

1. No staged changes: `git diff --cached --quiet` (already used in Case 2).
2. Worktree clean relative to `HEAD`: `git diff --quiet` (checks unstaged changes to tracked files only; untracked files are not "relative to `HEAD`").

If an untracked file would conflict with a file the fast-forward introduces, `git merge --ff-only` itself refuses to proceed and returns a non-zero exit with a clear git diagnostic. This is safe and aligns the implementation with the spec's wording.

**Pros:** aligns with the literal spec reading; users with harmless untracked files are fast-forwarded rather than warned; `git merge --ff-only` already guards against conflicting untracked files.
**Cons:** slightly less conservative than the current behaviour; a conflicting untracked file produces a raw git error rather than a talkbox warning (could be mitigated by catching the merge failure).

### Option B — Keep the current conservative behaviour

Leave `git status --porcelain` emptiness as the Case 1 condition. Untracked files are treated as dirty, causing fall-through to Case 2/3 and a warning.

**Pros:** maximally safe; no change required; untracked files can never interfere with a merge.
**Cons:** stricter than the spec's literal wording; users with harmless untracked files are warned rather than fast-forwarded.

### Option C — Allow untracked files except when they conflict

As Option A, but before running `git merge --ff-only`, check whether any untracked file would be overwritten by the merge (e.g. by comparing the worktree against the merge result tree). If a conflict is detected, warn with a talkbox-formatted message instead of letting git produce a raw error.

**Pros:** aligns with the spec; provides talkbox-formatted diagnostics for the conflicting-untracked-file case.
**Cons:** significantly more complex; the conflict-detection logic duplicates git's own checking; disproportionate effort for a rare edge case.

## Recommendation

**Option A.** It aligns the implementation with the spec's literal wording, improves the experience for users with harmless untracked files, and relies on `git merge --ff-only`'s existing safety guard for the conflicting case. The raw git error on conflict is acceptable since it is clear and the condition is rare.

## Selected option

**Option A (selected by the user).** Replace the `git status --porcelain` emptiness check with `git diff --cached --quiet` (no staged changes) and `git diff --quiet` (no unstaged tracked changes), allowing untracked files in Case 1. `git merge --ff-only`'s existing safety guard handles conflicting untracked files.
