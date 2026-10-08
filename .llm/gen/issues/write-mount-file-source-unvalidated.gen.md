# Issue: write mounts are not validated to be folders, and a failed populate leaks auto-created volumes

## affected files

- [lib/mounts.sh](../../../lib/mounts.sh) — `mount_spec`/`expand_mount`/`mount_entries` accept any source path without checking that it is a directory
- [lib/containers.sh](../../../lib/containers.sh) — `plan_volume_populate`/`plan_netbox_populate`/`plan_offbox_populate` copy with `cp -a /talkbox/source/.` and leave the named volumes auto-created by the `podman run -v` in place when the copy fails
- [talkbox.sh](../../../talkbox.sh) — no validation between option parsing and container creation

## description

Two related problems with non-folder write-mount sources:

1. **`onbox --write <file>` succeeds.** The file is bind-mounted read-write into the container and writes to it modify the host file. Verified: `onbox --write <file> -c --noninteractive 'echo hello > /host/write/<basename>'` returns 0 and rewrites the host file.
2. **`netbox`/`offbox --write <file>` fails ungracefully and leaks volumes.** The populate step runs a no-network temporary container with `-v <source>:/talkbox/source:ro -v <volume>:/talkbox/target` and `cp -a /talkbox/source/. /talkbox/target/`; for a file source this fails with the raw error `cp: cannot stat '/talkbox/source/.': Not a directory` and exit code 1. Because the named worktree and write volumes are referenced by the `-v` flags of that `podman run`, podman auto-creates them before the copy fails, and nothing removes them afterwards. Verified: after the failed run, `<slug>.netbox.worktree` and `<slug>.netbox.write.<dest-slug>` remain on the host while no container exists.

## spec violation

[SPEC.md](../../../SPEC.md) states under *read-write mounts*: "Read-write mounts must be folders on the host, not arbitrary files." The implementation performs no validation, so `onbox` silently accepts a file (contrary to the spec) and `netbox`/`offbox` fail with an unrelated `cp` diagnostic instead of a `talkbox:` usage error.

The stray-volume leak also contradicts the general hygiene expectation that failed container creation does not leave orphaned resources.

## impact

- `onbox` accepts a mount shape the spec forbids, giving write-mounts subtly different semantics across container types.
- `netbox`/`offbox` produce a confusing raw `cp` error and orphaned named volumes which retain a copy of nothing useful but still consume disk.

## suggested fix

Validate in `mount_entries` (or between parsing and planning) that every write-mount source is an existing directory, dying with a `talkbox:` message otherwise. Additionally, when `execute_plan` fails partway through the populate steps of `create_sandbox`, remove the named volumes that were auto-created by the failed `podman run` (or create the volumes explicitly after the source check so a failed copy leaves nothing behind).
