# Phase 29: Release automation for the main/dev branch split (`.release/release.sh`)

#flow/unified #model/big

## Aspects of the specification and issues

This phase implements repository-release automation, which is not covered by `SPEC.md` (the container specification); no `SPEC.md` behaviour is implemented or deferred. The requirements come from the release-convention review of `main` and `dev`:

- Every commit on `main` is the worktree of a `dev` commit with all `.coreignore`-matched files removed, `.coreignore` parsed with git's gitignore rules.
- The main commit message carries the release version in its subject and ends with a `Commit: <hash>` line holding the originating dev commit's hash.
- The main commit and the dev commit are tagged `v<version>` and `dev/v<version>` respectively, as lightweight tags.
- The user customizes the release notes in the main commit message via an editor, as currently done on `main`.
- The tooling lives in `.release/` on `dev`, and `.release/` is added to `.coreignore` so the release tooling never appears on `main`.

Design choices are recorded in the selected choice documents [release-script-tag-type](../choices/release-script-tag-type.gen.md) (lightweight tags on both branches), [release-script-commit-construction](../choices/release-script-commit-construction.gen.md) (temp-index plumbing), [release-script-message-editing](../choices/release-script-message-editing.gen.md) (editor over template) and [release-script-push-behaviour](../choices/release-script-push-behaviour.gen.md) (no push).

## External-facing functionality

`.release/release.sh <version>` (run from the repository root, on the `dev` branch) performs the whole release:

1. Validates the invocation: exactly one `<version>` argument (e.g. `v0.1.3` or `0.1.3`; the `v` prefix is normalized), the current branch is `dev`, the worktree is clean relative to `dev HEAD` (so the release commit is exactly the committed state), the `main` branch exists, and neither `v<version>` nor `dev/<version>` tags exist yet.
2. Resolves the release dev commit as `dev` HEAD.
3. Reads `.coreignore` **from the dev commit** (`git show <dev>:​.coreignore`, with an empty filter when absent) and computes the set of dev-tree paths matched by it, using git's gitignore semantics (`git check-ignore --exclude-from` with the extracted file over the `git ls-tree -r --name-only` listing of the dev commit).
4. Builds the main tree from the dev commit's tree minus the matched paths, via a temporary index: read the dev tree into a `GIT_INDEX_FILE`, `git update-index --force-remove` each matched path, `git write-tree`.
5. Composes a message template (`talkbox v<version>` subject, blank line, a release-notes placeholder, trailing `Commit: <dev-hash>` line), opens it in the user's editor (`$GIT_EDITOR`/`$EDITOR`), and re-reads the edited message; the script validates that the version appears in the subject and the message ends with the `Commit: <hash>` line, and aborts on an empty/unedited-without-notes edit or a non-zero editor exit.
6. Creates the main commit with `git commit-tree`, using the edited message, the pruned tree, and the current `main` HEAD as parent; advances `main` with `git update-ref` (the worktree stays on `dev`, untouched).
7. Creates the lightweight tags `v<version>` on the new main commit and `dev/<version>` on the dev commit.
8. Prints a summary (main commit, dev commit, tags) and leaves pushing to the user (no push step).
9. Fails cleanly (non-zero, `release: <message>` diagnostics) on any validation failure, pre-existing tag, missing branch, editor failure, or a main worktree divergence; no partial state (refs are only updated after all inputs are validated; tags are only created after the commit succeeds).

## Key internal design

- **`.coreignore` filtering with git gitignore rules**: `git check-ignore --stdin --exclude-from=<coreignore file>` applies to the dev tree listing, so directory patterns (`test/`), bare names (`.llm/`) and negations are evaluated with the exact gitignore semantics; a `.coreignore` matched path is removed from the temp index with `git update-index --force-remove`. `.coreignore` itself is matched by its own first pattern and therefore excluded from main.
- **Tree construction never touches the working tree**: plumbing only (`git ls-tree`, `git read-tree` into a temporary `GIT_INDEX_FILE`, `git update-index`, `git write-tree`, `git commit-tree`, `git update-ref refs/heads/main`), so the script is safe to run on a checked-out `dev`.
- **Message flow**: the message is written to a temporary file with the template, the editor runs on it, and the final message is validated to end with the exact `Commit: <dev-hash>` line (preserved from the template so the hash cannot be corrupted).
- Failure-cleanup: temporary files (extracted `.coreignore`, temporary index, message file) are removed via `trap`.

## Files to be created

- `.release/release.sh` — the release script implementing the above; self-contained Bash with usage/`-h`/`--help`, structured into validation, coreignore filtering, tree construction, message editing, commit and tagging steps.

## Files to be modified

- `.coreignore` — add the `.release/` entry so the release tooling never reaches `main`.

## Relevant files to read during implementation

- `.coreignore` — the current ignore patterns and their gitignore-style shape.
- `main` and `dev` branch history (`git log main`, `git log dev`, `git show v0.1.2`, tags `v0.1.2`/`dev/v0.1.2`) — the release message, `Source:`/`Commit:` trailer and tag conventions to be reproduced (with the new `Commit:` trailer replacing `Source:`).
- The choice documents under `.llm/gen/choices/` listed above.
- `lib/common.sh` — repo conventions for `die()`-style diagnostics and shell style (the script is standalone and does not source `lib/`, but should follow the same style).

## Key internal interfaces

- `release.sh <version>` — the single entry point.
- Internal steps: version/branch/cleanliness validation; `coreignore` extraction and path filtering (`git check-ignore` over `git ls-tree` output); temp-index tree pruning; message template, editing and validation; `git commit-tree` + `git update-ref refs/heads/main`; `git tag` for `v<version>` (main commit) and `dev/<version>` (dev commit).

## Tests

Per the request, no tests are implemented for this phase. The script must pass `make lint` (ShellCheck) and `make format` (shfmt), which the implementer should run; a manual smoke check (running `.release/release.sh` in a scratch clone or observing a real release) is performed by the user rather than an automated test suite.
