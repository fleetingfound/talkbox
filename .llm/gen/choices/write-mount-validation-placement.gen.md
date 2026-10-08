# Choice: Placement of the write-mount folder validation

## context

[SPEC.md](../../../SPEC.md) states "Read-write mounts must be folders on the host, not arbitrary files", but no validation is performed anywhere. With a file as a write-mount source, `onbox` silently bind-mounts it read-write (writes modify the host file), while `netbox`/`offbox` fail with the raw `cp: cannot stat '/talkbox/source/.': Not a directory` diagnostic from the populate step, after volumes have already been auto-created (see the issue [write-mount-file-source-unvalidated](../issues/write-mount-file-source-unvalidated.gen.md)).

Every write-mount spec — from `defaults/write.mounts` and from CLI `--write` arguments, for all three container types — flows through `mount_entries` in [lib/mounts.sh](../../../lib/mounts.sh). `onbox` consumes its output via `mount_args`, while `netbox`/`offbox` consume the `mount_entries` output directly (plus `mount_volume_args`).

## options

### Option A: Inside `mount_entries`, mode-conditional (Recommended)

When the mode is `write`, validate during parsing that every resolved source is an existing directory, dying with a `talkbox:` message naming the offending source otherwise. Read mounts are unaffected.

- **Pros:** A single choke point covering the defaults file, CLI arguments and all three container types; the error surfaces before any podman call, so no volumes or containers can be created from an invalid mount; consistent with the existing `die` diagnostic style.
- **Cons:** `mount_entries` is no longer a pure parser — it performs a filesystem check with a fatal failure mode.

### Option B: In `container_action` after the write-mount parse

Add a validation loop over the parsed write-mount sources in [talkbox.sh](../../../talkbox.sh), between parsing and dispatch.

- **Pros:** Keeps `mount_entries` pure; the dispatcher is the natural place for usage errors.
- **Cons:** The `onbox` and `netbox`/`offbox` branches parse write mounts through different helpers (`mount_args` vs `mount_entries`), so the loop must be placed to cover both, or duplicated; future callers of `mount_entries` bypass the check.

### Option C: In the container planners

Validate the write-mount sources in `lib/containers.sh` at plan time, per container family.

- **Cons:** Duplicates the check across the `onbox` and `netbox`/`offbox` plan paths; validation runs later than necessary.

## recommendation

**Option A.** Every write-mount parse in the codebase flows through `mount_entries`, so a mode-conditional directory check there is the minimal change which guarantees the spec invariant for all container types and both spec sources, failing before any podman state is created.

## selected option

**Option A** (selected by the user). `mount_entries` dies with a `talkbox:` message when a write-mode source is not an existing directory.
