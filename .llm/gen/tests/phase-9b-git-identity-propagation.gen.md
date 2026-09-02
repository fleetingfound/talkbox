# Tests: Phase 9b — Git identity propagation into containers

Linked plan: [phase-9b-git-identity-propagation.gen.md](../plans/phase-9b-git-identity-propagation.gen.md)

Summary: this phase adds red-green tests for propagating the host's effective git `user.name`/`user.email` into the `onbox`, `netbox` and `offbox` containers — a host-side `host_git_identity` helper in `lib/git.sh`, `--env TALKBOX_GIT_USER_NAME`/`TALKBOX_GIT_USER_EMAIL` flags appended by the three planners inside the `git_mounts_enabled` block, and an `entrypoint.sh` block writing the values to `/home/dev/.gitconfig` on every start — per [Choice: Git identity propagation into containers](../choices/git-identity-propagation.gen.md) (Option A) and the **git as transport** section of [SPEC.md](../../../SPEC.md) (lines 264-283).

## New tests

Unit tests:

- `test/unit/git.bats` — three tests for the new `host_git_identity` helper (the plan's Test bullet: "The new `lib/git.sh` helper returns the expected two-line output for a temporary git repo with `user.name`/`user.email` set, and omits the absent field when only one is configured (or returns nothing when neither is set)"):
  - `host_git_identity prints the effective user.name and user.email in order` — asserts the two-line `host-user\nhost@example.com` output for a repo with both values configured.
  - `host_git_identity omits a field the host has not configured` — with an isolated `HOME`/`GIT_CONFIG_NOSYSTEM`, only `user.name` is set and the output is exactly `host-user`.
  - `host_git_identity prints nothing when no identity is configured` — with an isolated `HOME`/`GIT_CONFIG_NOSYSTEM` and no local identity, the output is empty.
- `test/unit/containers.bats` — two `plan_onbox` tests:
  - `onbox plan emits git identity env vars for a git-tracked project but not for a non-git project` — asserts the create-argument array contains tokens with `TALKBOX_GIT_USER_NAME=host-user` and `TALKBOX_GIT_USER_EMAIL=host@example.com` for a git-tracked project and no `TALKBOX_GIT_USER` token for a non-git folder (the plan's Test bullet: the planners "emit `--env TALKBOX_GIT_USER_NAME=...` / `--env TALKBOX_GIT_USER_EMAIL=...` tokens (with the host values) inside the create-argument list when git mounts are enabled, and emit no such tokens when git mounts are disabled (non-git project)").
  - `onbox plan omits a git identity env var for a field the host has not configured` — with an isolated `HOME`/`GIT_CONFIG_NOSYSTEM` and only `user.email` set, no `TALKBOX_GIT_USER_NAME` token is emitted while `TALKBOX_GIT_USER_EMAIL=host@example.com` is (the plan's "Emit no `--env` for an absent value").
- `test/unit/netbox-offbox.bats` — `netbox plan emits git identity env vars for a git-tracked project but not for a non-git project` and the analogous `offbox` test, asserting the same positive and negative behaviour through `plan_netbox`/`plan_offbox`.

End-to-end tests (`test/e2e/git-identity.bats`), run noninteractively with `-c` per the plan's Test bullets, each for `onbox`, `netbox` and `offbox`:

- `onbox/netbox/offbox container git identity matches the host user.name and user.email` — creates a container for a temporary git repo whose local config sets `user.name talkbox-test` / `user.email test@example.com`, runs `git config user.name && git config user.email` inside the container and asserts both host values are returned ("verifying the entrypoint wrote the global config").
- `onbox/netbox/offbox commits are attributed to the host git identity` — runs `git commit --allow-empty -m identity-commit` inside the container and asserts `git log --format="%an <%ae>" -1` yields `talkbox-test <test@example.com>` (the plan's "an empty-commit made inside the container is attributed to the host identity").

Against the current (unimplemented) code all 7 unit and 6 e2e tests fail for the correct reason: `host_git_identity` is undefined (command-not-found), the planners emit no `TALKBOX_GIT_USER_*` tokens, and inside the containers `git config user.name` exits non-zero and `git commit` aborts with "Please tell me who you are" — none of which is a test-implementation error or timeout.

## Tests edited

- `test/unit/git.bats` — a file-level `# shellcheck disable=SC2030,SC2031` comment was added to silence shellcheck info-level warnings about `HOME`/`GIT_CONFIG_NOSYSTEM` being exported inside the bats test subshell; this matches the existing pattern already used by `test/e2e/git-transport.bats` (`# shellcheck disable=SC2030,SC2031 # bats runs setup/test/teardown in one subshell`) and is required so `make lint` passes with the new tests.
- No existing test assertions were changed. In particular, the pre-existing git-transport / merge / sync tests which configure an identity inside the container by hand (`git config user.email ... && git config user.name ...`, writing to the repo-local `.git/config`) remain valid after implementation because local config takes precedence over the propagated global `/home/dev/.gitconfig` — exactly as the plan states in its Test section: "the existing git-transport / merge / sync tests ... set `user.name`/`user.email` inside the container by hand and must continue to override the propagated global config, since `git config user.name <v>` in a repo writes to the local `.git/config` which takes precedence over the global `/home/dev/.gitconfig`". The `onbox gitdir volume is a fresh git directory ... not a copy of the host git dir` test likewise stays valid: it greps the gitdir *volume's* `config` file for `test@example.com`, and the propagated identity is written to `/home/dev/.gitconfig`, not to the volume.

## Tests removed

- None. No pre-existing test is inconsistent with the plan: the plan only adds host→container identity propagation that is absent today ("the container simply has no identity set (unchanged from today)" when the host has none, and "if the host has no `user.name`/`user.email` configured, container creation proceeds normally"), so every existing unit and e2e test continues to pass after implementation.
