# Issue: `--rm-container`, `--recontain` and `--rebuild` do not remove or recreate named volumes

## affected files

- [lib/containers.sh](../../../lib/containers.sh) — `plan_rm_container`, `plan_netbox_rm_container`, `plan_offbox_rm_container`, `plan_recontain`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_rebuild`, `plan_netbox_rebuild`, `plan_offbox_rebuild`

## description

The lifecycle verbs rely on `podman rm -f --volumes <container>` to remove "associated volumes". However, the named volumes used by talkbox (`<slug>.<container>.gitdir`, `<slug>.netbox.worktree`, `<slug>.netbox.write.<dest-slug>`, `<slug>.offbox.worktree`, `<slug>.offbox.write.<dest-slug>`) are created explicitly with `podman volume create` and then mounted with `-v <name>:<path>`. Podman's `--volumes` flag only removes **anonymous** volumes associated with a container; explicitly-created named volumes survive `podman rm -f --volumes` and are left orphaned.

This was verified empirically:

- `onbox --rm-container` leaves `<slug>.onbox.gitdir` behind.
- `netbox --rm-container` leaves `<slug>.netbox.worktree`, `<slug>.netbox.write.<dest-slug>` and `<slug>.netbox.gitdir` behind.

For `--recontain` and `--rebuild`, the stale named volumes are then **reused** rather than recreated, because the populate/gitdir-volume helpers (`plan_gitdir_volume`, `plan_netbox_populate`, `plan_offbox_populate`) are idempotent — they skip creation when the volume already exists, and `plan_volume_populate` copies into the existing volume with `cp -a source/. target/` (a merge, not a clean recreation). This was verified: after `onbox --recontain`, the gitdir volume still contains the container's previous commit, and the worktree volume retains stale container-created files.

## spec violation

[SPEC.md](../../../SPEC.md) states:

- "`onbox --rm-container` removes the `onbox` container, **together with associated volumes**"
- "`onbox --recontain` recreates the `onbox` container and **all of its associated volumes** and then starts the container"
- "`onbox --rebuild` rebuilds the base image and **recreates the `onbox` container** and then starts the container"

The "associated volumes" for onbox are the gitdir volume; for netbox/offbox they are the worktree, write and gitdir volumes. None of these are currently removed or recreated.

## impact

- **`--rm-container`**: orphaned named volumes accumulate on the host, consuming disk space and potentially leaking project data (including git history in the gitdir volume) after the user believes they have been removed.
- **`--recontain` / `--rebuild`**: the user receives a container whose filesystem is fresh but whose git history and (for netbox/offbox) worktree/write volumes retain stale content from the previous container. `git log` inside a "freshly recontained" container still shows old container commits, contradicting the expectation of a clean recreation.

## suggested fix

Before the `podman rm -f --volumes <container>` step (or in addition to it), explicitly remove the named volumes associated with the container using `podman volume rm -f <volume-name>` for each volume that exists. The volume names are already derivable via the naming helpers in [lib/naming.sh](../../../lib/naming.sh) (`gitdir_volume`, `netbox_worktree_volume`, `offbox_worktree_volume`, `netbox_write_volume`, `offbox_write_volume`). The write-volume dest-slug list is available from the parsed write-mount entries.
