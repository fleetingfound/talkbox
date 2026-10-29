# `onbox merge` fails the git-history probe on machines where the podman volume mountpoint is not host-visible

## Files

- `lib/git.sh` — `require_git_history` (lines 213-224): host-side probe of the volume mountpoint.

## Description

`require_git_history` validates the gitdir volume via a host filesystem check:

```bash
mountpoint="$(podman volume inspect --format '{{.Mountpoint}}' "$vol" 2>/dev/null)"
[[ -z "$mountpoint" || ! -e "$mountpoint/HEAD" ]] && die "no git history ... start the container first"
```

`podman volume inspect` returns the mountpoint path *on the machine where the podman service/daemon lives* (`/var/lib/containers/storage/volumes/...` for UID 0, `$HOME/.local/share/...` for rootless, a VM path under `podman machine`). `[[ -e $mountpoint/HEAD ]]` then stats that path from the talkbox client machine and user. The check passes only when the talkbox CLI runs with filesystem access to the podman service's volume storage; it fails whenever podman is rootful (system service / docker-compat socket: `/var/lib/containers` is root-only), remote over ssh, a `podman machine` VM, or the inspect fails while its stderr is suppressed. A failure produces the misleading "no git history … start the container first" error even though the volume has full history, and it is machine-dependent (`onbox fetch` works because it never host-stats the volume). Any transient inspect error is also silently converted into the same message by `2>/dev/null` + empty-string check. The probe should be podman-based (e.g. a no-network `podman run` with the volume mounted, checking for `HEAD`) instead of a host-side stat of the inspect-reported path.
