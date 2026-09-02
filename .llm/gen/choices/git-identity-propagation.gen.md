# Choice: Git identity propagation into containers

#flow/redgreen

## Context

`SPEC.md` (git as transport, lines 264-283) notes that `git` is used inside `onbox`/`netbox`/`offbox` containers both to make in-container changes visible on the host and to transport committed history back to the host via bundles. Bundles intentionally do **not** carry git config or hooks (line 273), so the container's own git repository — a fresh gitdir volume initialised by [image/entrypoint.sh](../../../image/entrypoint.sh) — starts with no `user.name`/`user.email`. Commits made inside the container are therefore attributed to an unspecified identity unless the user sets one by hand each session.

Phase 9b ensures the host's effective `user.name` and `user.email` are copied into the `onbox`, `netbox` and `offbox` containers so that commits made inside them are attributed to the host user without manual configuration.

The host's git identity can originate from system (`/etc/gitconfig`), global (`~/.gitconfig`, `~/.config/git/config`) or the project's local `<project>/.git/config`. The project's local config is not directly available inside the container: the host git dir is bind-mounted read-only at `/host/git/` and the container writes to its own separate gitdir volume (`<project-slug>.<container>.gitdir`), so the local config is not inherited.

Each container's gitdir volume is distinct (`onbox`/`netbox`/`offbox`) and is (re)initialised by [image/entrypoint.sh](../../../image/entrypoint.sh) when absent. `netbox`/`offbox` root filesystems are inherited from `onbox`/`netbox` via `podman commit`, but runtime `-e` environment variables passed to `podman create` are **not** baked into the committed image, so any propagation mechanism must apply at each container's own create/start path rather than relying on inheritance.

The open design question is the mechanism by which the host's `user.name`/`user.email` reach the container's git configuration, and where in the container filesystem that configuration is written.

## Option A — env vars at create time + entrypoint writes global config (Recommended)

Read the host's effective `user.name`/`user.email` once at plan time (only when `git_mounts_enabled "$project"` is true, i.e. the same guard already used for the git mounts) via `git -C "$project" config user.name` / `user.email`. Pass the two values to `podman create` as environment variables (e.g. `TALKBOX_GIT_USER_NAME` / `TALKBOX_GIT_USER_EMAIL`) in `plan_onbox`, `plan_netbox` and `plan_offbox`. Have [image/entrypoint.sh](../../../image/entrypoint.sh) write them to the container user's **global** git config (`/home/dev/.gitconfig`) on every start, mirroring the existing dotfiles-copy block, and only when the variables are non-empty.

- Single source of truth: the three planners already assemble every create argument, so all create/recontain/rebuild paths inherit the behaviour automatically, exactly as GPU support did in Phase 7.
- Survives `podman commit` inheritance correctly because the env vars are re-emitted at each container's own `podman create`; netbox/offbox do not rely on the values being baked into the committed image.
- Writing to `/home/dev/.gitconfig` (global, not the repo's `.git/config`) means: `git config user.name` reads return the value (tools/scripts that probe config work); the value applies to every repository in the container; and it does not collide with the entrypoint's `git init`/`fetch`/`reset` block which only touches the repo when it is absent.
- Re-applied on every container start (like dotfiles), so a value changed inside the container is re-synced to the host identity on next start — consistent with the "identity follows the host" intent.
- Missing values: when `git -C "$project" config user.name` exits non-zero (host has no identity configured), emit no env var; the entrypoint skips writing. A stderr warning from the planner is acceptable but must not abort container creation.
- Source scope: effective value (system + global + local for the project), so the host user's project-specific identity is honoured.

## Option B — `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars only

Pass the four standard git identity environment variables (`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`) to `podman create` in the three planners, read from the host's effective config at plan time. No entrypoint change.

- Simplest: no entrypoint or image change; purely planner-side.
- Git commits inside the container are attributed to the host user.
- However, `git config user.name` / `git config user.email` reads inside the container return empty, so any tool or script that probes config (rather than relying on the env override) sees no identity. This is a behavioural gap versus Option A.
- Env vars passed to `podman create` are still not preserved by `podman commit`, so they must be re-passed at each create path — same threading requirement as Option A but with four vars instead of two and no entrypoint to normalise them.

## Option C — write to the container repo's local `.git/config` during git init only

Have [image/entrypoint.sh](../../../image/entrypoint.sh) read the host identity (passed via env vars as in Option A, or read from `/host/git/config`) and write `user.name`/`user.email` into `/working/<project-base>/.git/config` inside the `if ! git -C "$repo" rev-parse --git-dir` init block.

- The values persist in the container's gitdir volume across restarts, so no re-sync is needed on subsequent starts of the same container.
- But: the init block only runs when the repo is absent, so a value changed on the host is never propagated to an already-initialised container. The host identity drifts.
- Only the project repo gets the config; any other repository the user clones inside the container does not.
- Reading from `/host/git/config` directly would only capture the host's *local* config, missing system/global identity — narrower than reading the effective value on the host.

## Selection

**Option A** — env vars at create time + entrypoint writes global config. (Selected.)
