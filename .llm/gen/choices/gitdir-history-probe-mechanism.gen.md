# Choice: gitdir history probe mechanism for `require_git_history`

## Context

`require_git_history` in `lib/git.sh` (used by `run_merge` and `run_sync`) validates that the gitdir volume holds a git history before merging/syncing. It currently does this with a host-side stat of the path returned by `podman volume inspect --format '{{.Mountpoint}}'`, which fails whenever the mountpoint is not visible to the CLI user (remote podman/machine, rootful podman, custom `volume_path`) and conflates inspect failures with "no history" via `2>/dev/null` + the empty-string check. The issue `.llm/gen/issues/onbox-merge-gitdir-volume-host-path-check.gen.md` requires a probe that works in all podman configurations. The check is used by both `onbox merge` and `onbox sync` (sync does not run a bundle fetch, so the check cannot ride on bundle-failure handling).

## Option A (Recommended): no-network `podman run` volume-mounted HEAD probe

Assemble the probe as a `podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000` command (via `plan_no_net_run`) mounting the gitdir volume read-only at `/gitdir` and running `test -e /gitdir/HEAD` (or the image's shell equivalent) in the base image, mirroring the existing `gitdir_bundle_cmd` pattern. The volume-exists check (`require_gitdir_volume`) stays as-is; the mountpoint inspection is removed entirely. Works under remote, rootful and rootless podman alike, since the check runs inside the podman backend's own filesystem view. Cost: one extra short-lived container per `merge`/`sync` invocation.

## Option B: drop the pre-check and rely on downstream failure

Remove `require_git_history`'s content check and let the bundle fetch (merge) or in-container sync (sync) fail on an empty gitdir, mapping the failure to a friendly message. No extra container run, but `sync` has no bundle fetch to lean on, and the "start the container first" guidance would be lost or duplicated downstream.

## Option C: keep the host stat, add a podman fallback only on failure

Keep the host-side stat as a fast path, fall back to the podman probe when the stat fails. Fastest in the common rootless case but keeps the mountpoint path in the code and the inspect machinery; the fallback branches double the test matrix.

## Recommendation

Option A: it is the only option that is uniformly correct across remote, rootful and rootless podman, matches the issue's fix direction and the codebase's existing no-network-probe pattern, and it removes the only host-side filesystem dependency in the fetch/merge/sync transport.

## Selection

**Option A: no-network `podman run` volume-mounted HEAD probe.** Selected by the user.
