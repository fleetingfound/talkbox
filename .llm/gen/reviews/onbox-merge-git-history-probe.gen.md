# Investigation: `onbox merge` reporting "no git history in the onbox gitdir volume" despite an existing multi-commit history

## Where the message comes from

- `onbox merge` dispatches to `run_merge` (`lib/git.sh`), which first calls `require_git_history` (`lib/git.sh:213-224`):

```bash
vol="$(gitdir_volume "$project" "$container")"                       # "<project-slug>.onbox.gitdir" (lib/naming.sh:37-39)
mountpoint="$(podman volume inspect --format '{{.Mountpoint}}' "$vol" 2>/dev/null)"
if [[ -z "$mountpoint" || ! -e "$mountpoint/HEAD" ]]; then
    die "no git history in the $container gitdir volume; start the container first" 1
fi
```

The probe passes the earlier guards — the repo is a git repository, the volume exists (`require_gitdir_volume` → `podman volume exists`, a pure podman API check) — and then dies either because `podman volume inspect` returned an empty string, or because `[[ -e "$mountpoint/HEAD" ]]` (a **host-side stat of the volume's on-disk `_data` path**) fails.

The check is the only place in the `fetch`/`merge`/`sync` transport that touches the volume contents from the host filesystem. Everything else goes through podman: `gitdir_volume_exists` (API), the bundle fetch (`gitdir_bundle_cmd` runs `git bundle create` inside a `podman run` with the volume mounted at `/gitdir`). That is why `onbox fetch` and manual git merging work on the affected machines while `merge`/`sync` (both call `require_git_history`) fail: the volume and its history are intact; only the host-side stat of the inspect-reported path fails.

## Environment-dependent causes, ranked by likelihood

1. **Podman talks to a different machine/VM than the one running `onbox merge`.** With `podman --remote`/`podman machine` (WSL2, macOS) or a `CONTAINER_HOST`/`docker`-style connection, `podman volume exists` and `volume inspect` succeed via the API, but `Mountpoint` is a path *inside the remote instance* (`$HOME/.local/share/containers/storage/volumes/<slug>.onbox.gitdir/_data` in the VM), which does not exist on the host filesystem where `[[ -e ]]` runs. Documented in `.llm/ref/podman.docs/podman-remote.1.md`: podman-remote is a local client over an API tunnel; inspect results describe the backend node.

2. **Rootful podman / podman system service.** For UID 0 the volume path root is `/var/lib/containers/storage/volumes` (see `.llm/ref/podman.docs/podman.1.md:247`), which is `0700 root:root`. A non-root user cannot traverse it, so `[[ -e "$mountpoint/HEAD" ]]` fails for a volume that is fully populated. Under SELinux the `_data` files also carry container labels, though plain DAC traverse denial is sufficient to explain it. `podman volume exists`/`inspect` still succeed because they only query podman, so the volume check passes and only the stat fails.

3. **`podman volume inspect` failure suppressed by `2>/dev/null`.** Any inspect error (daemon connection, transient failure, stderr from a profile warning) yields an empty `mountpoint`, which the `[[ -z ]]` arm converts into the same "no git history … start the container first" message. The guard conflates "inspect failed" with "volume has no HEAD".

4. **Go-template field name on old podman.** With `--format`, an unknown field name renders as the literal `<no value>`, not an error: on a podman old enough to spell the field `MountPoint` (v1-era volume inspect), `{{.Mountpoint}}` yields `<no value>`, the path `<no value>/HEAD` never exists, and every merge/sync on that machine fails this way. (`podman-volume-inspect.1.md:38` documents the current `Mountpoint` placeholder.)

5. **Custom `volume_path` in `containers.conf`** pointing outside a user-traversable location — same effect as (2) but rarer.

The unit tests encode the assumption behind this design: `PODMAN_MOUNTPOINTS` in `test/unit/git-transport.bats` maps volume names to *host* paths, and `require_git_history` probes `"$mountpoint/HEAD"` directly (the "empty-mountpoint" test at line 331-344).

## Why the user's observations are consistent with all of this

- The container has a real multi-commit history: `image/setup.sh` initializes the gitdir volume (mounted at `/working/<base>/.git`) via `git init`, so `HEAD` exists at the volume root.
- `onbox fetch` works: `run_fetch` uses `gitdir_volume_exists` (`podman volume exists`) and creates the bundle *inside* a container with the volume mounted — no host-side path check.
- Manual git merging works: all git operations run against the host repo, bypassing `require_git_history` entirely.
- "On some machines": only machines where the stat of the inspect-reported mountpoint path is visible to the CLI user — i.e. plain rootless local podman (mountpoint under `~/.local/share/containers/storage/volumes/...`, owned by the user, `HEAD` written under `keep-id:uid=1000` so it is user-readable) — pass; rootful/service/remote podman users fail.

## Diagnostic steps

```bash
vol="$(basename "$(git rev-parse --show-toplevel)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-+/-/g; s/^-//; s/-$//').onbox.gitdir"
podman volume inspect --format '{{.Mountpoint}}' "$vol"     # is this path readable/valid on this machine?
podman run --rm --network=none -v "$vol":/gitdir:ro \
  -e GIT_DIR=/gitdir talkbox/base:latest git rev-parse HEAD   # probe HEAD via podman, the way fetch does
podman volume ls | grep gitdir   # confirm the volume exists and history is intact
```

If the `podman run` probe succeeds while `[[ -e "$(podman volume inspect --format '{{.Mountpoint}}' "$vol")/HEAD" ]]` fails, the mountpoint probe is the culprit. The fix direction is tracked in [the issue](../issues/onbox-merge-gitdir-volume-host-path-check.gen.md): replace the host-side stat with a podman-backed probe (e.g. a no-network `podman run` with the volume mounted, checking `HEAD`, mirroring the existing `gitdir_bundle_cmd` pattern) so the check works under remote/rootful podman, and stop discarding the inspect stderr so genuine failures are distinguishable.
