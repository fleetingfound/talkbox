# Plan: Phase 9b — Propagate host git `user.name`/`user.email` into containers

#flow/redgreen #model/default

## Specification scope

Implements a behavioural requirement implied by the **git as transport** section of [SPEC.md](../../../SPEC.md) (lines 264-283): the host's git identity (`user.name` and `user.email`) is copied into the `onbox`, `netbox` and `offbox` containers so that commits made inside them are attributed to the host user without manual configuration.

`SPEC.md` line 273 notes that git bundles intentionally do not transfer git config or hooks from the container to the host; this phase addresses the reverse direction (host → container), which is not blocked by the bundle transport. The container's gitdir volume is a fresh repository initialised by [image/entrypoint.sh](../../../image/entrypoint.sh) and otherwise carries no host identity.

No other aspect of `SPEC.md` / `SPEC.gen.md` is altered. (There is no `SPEC.gen.md`.)

The design follows [Git identity propagation into containers](../choices/git-identity-propagation.gen.md) — Option A: host effective `user.name`/`user.email` are read at plan time, passed as env vars to `podman create` in all three planners, and the entrypoint writes them to `/home/dev/.gitconfig` on every start.

## To be implemented

- Add a host-side helper (in [lib/git.sh](../../../lib/git.sh), alongside the other host git helpers) that, given a project, prints the effective `user.name` and `user.email` (two lines, in that order) by running `git -C "$project" config user.name` / `user.email`. When either value is absent (git exits non-zero), print nothing for that field. This helper is only meaningful when `git_mounts_enabled "$project"` is true; callers guard on that predicate (as the existing git mount plumbing already does).
- In [lib/containers.sh](../../../lib/containers.sh), inside `plan_onbox`, `plan_netbox` and `plan_offbox`, within the existing `if git_mounts_enabled "$project"; then` block, read the host identity via the new helper and append `--env` flags (`TALKBOX_GIT_USER_NAME` / `TALKBOX_GIT_USER_EMAIL`) to the create-argument list for each non-empty value. Emit no `--env` for an absent value; optionally emit a stderr warning from the planner when the host has no `user.name` or `user.email` configured, but never abort container creation.
- In [image/entrypoint.sh](../../../image/entrypoint.sh), add a block (alongside the existing dotfiles-copy block, run on every start) which, when `TALKBOX_GIT_USER_NAME` is non-empty, runs `git config --global user.name "$TALKBOX_GIT_USER_NAME"`, and likewise for `TALKBOX_GIT_USER_EMAIL` when non-empty. This writes to `/home/dev/.gitconfig`. Guard so that empty/unset variables leave existing config untouched.

Because the three planners are the single source of truth for create arguments, the default-create (`run_onbox`/`run_netbox`/`run_offbox`), recontain and rebuild paths all inherit git identity propagation automatically with no further changes, exactly as GPU support (Phase 7) did. Because the env vars are re-emitted at each container's own `podman create`, `netbox`/`offbox` inheritance via `podman commit` is handled correctly (committed images do not preserve runtime `-e` vars, but each container re-passes its own).

## To be deferred

- Propagation of any git config keys other than `user.name` and `user.email` (e.g. `core.editor`, signing keys, `init.defaultBranch`). The phase is scoped to identity only, per the request.
- Propagation into the temporary no-network helper containers used by `plan_volume_populate` and the `container_sync_cmd` fallback `podman run`. These perform only file copies or git fetch/merge operations against pre-existing history and do not create commits, so they have no need for an author identity.
- A mechanism to override or disable propagation (e.g. a `--no-git-identity` flag). Not requested; the host identity always applies when git mounts are enabled.
- Behaviour when the project is not git-tracked: git identity propagation is gated on `git_mounts_enabled`, which is already false for non-git projects, so no work is needed there.

## External-facing functionality

When `onbox`, `netbox` or `offbox` create a container for a git-tracked project whose git directory lies inside the project, the host's effective `user.name` and `user.email` are available inside the container as global git config. Consequently, `git commit` inside the container attributes commits to the host user, and `git config user.name` / `git config user.email` inside the container return the host values, without the user needing to configure them by hand. If the host has no `user.name`/`user.email` configured, container creation proceeds normally and the container simply has no identity set (unchanged from today).

## Files to be created

- None.

## Files to read during implementation

- [lib/git.sh](../../../lib/git.sh) — add the host identity helper near `git_mounts_enabled`/`resolve_git_dir`.
- [lib/containers.sh](../../../lib/containers.sh) — `plan_onbox`, `plan_netbox`, `plan_offbox`: append `--env` flags inside the `git_mounts_enabled` block.
- [image/entrypoint.sh](../../../image/entrypoint.sh) — add the global git config write block.
- [image/Containerfile](../../../image/Containerfile) — confirm the entrypoint is already copied in and no image change is required beyond the entrypoint edit (the entrypoint is `COPY`ed at build time, so a `--rebuild` is needed to pick up the change; this is a usage note, not a Containerfile edit).
- [talkbox.sh](../../../talkbox.sh) — confirm no dispatcher changes are required (the planners consume the new helper directly).

## Key internal interfaces

- A new host-side helper in `lib/git.sh` (e.g. `host_git_identity <project>`) printing the effective `user.name` and `user.email`, two lines, absent values omitted. Pure-ish like the other git helpers (invokes `git -C`).
- `TALKBOX_GIT_USER_NAME` / `TALKBOX_GIT_USER_EMAIL` — environment variables passed to `podman create` by the three planners and consumed by `entrypoint.sh`. These are container-runtime env vars, distinct from the existing `TALKBOX_*` host-side option globals (`TALKBOX_GPU`, `TALKBOX_FRESH`, etc.); they are not parsed by `lib/options.sh`.

## Tests

Requires tests, both unit and end-to-end.

- **Unit tests:**
  - The new `lib/git.sh` helper returns the expected two-line output for a temporary git repo with `user.name`/`user.email` set, and omits the absent field when only one is configured (or returns nothing when neither is set).
  - The three planners emit `--env TALKBOX_GIT_USER_NAME=...` / `--env TALKBOX_GIT_USER_EMAIL=...` tokens (with the host values) inside the create-argument list when git mounts are enabled, and emit no such tokens when git mounts are disabled (non-git project). These can be asserted against the nameref-populated plan array without invoking `podman`, mirroring the existing planner unit tests.
- **End-to-end tests:**
  - A noninteractive `-c` e2e test (onbox, and analogously netbox/offbox) that, after creating a container for a temporary git repo with a known host `user.name`/`user.email`, runs `git config user.name` / `git config user.email` inside the container and asserts they match the host values — verifying the entrypoint wrote the global config.
  - The same e2e shape should confirm that an empty-commit made inside the container is attributed to the host identity (assert via `git log --format='%an <%ae>'`).
  - Run the full e2e suite to confirm no regressions in existing git-transport / merge / sync tests (which set `user.name`/`user.email` inside the container by hand and must continue to override the propagated global config, since `git config user.name <v>` in a repo writes to the local `.git/config` which takes precedence over the global `/home/dev/.gitconfig`).
