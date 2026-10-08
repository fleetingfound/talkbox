# Phase 23a: Write-mount folder validation and failed-creation volume rollback

#flow/redgreen #model/default

Resolves the issue [write mounts are not validated to be folders, and a failed populate leaks auto-created volumes](../../issues/write-mount-file-source-unvalidated.gen.md).

## specification

Implements the [SPEC.md](../../../SPEC.md) *read-write mounts* requirement: "Read-write mounts must be folders on the host, not arbitrary files." It also enforces the general hygiene expectation that a failed container creation does not leave orphaned resources behind.

No other aspect of the specification is affected; everything else is already implemented and deferred here.

## external-facing functionality

- Any `onbox`, `netbox` or `offbox` invocation in which a write-mount spec — from `defaults/write.mounts` or a `--write` argument — resolves to a source that is not an existing directory fails with a `talkbox:` diagnostic naming the offending source, before any podman container or volume is created. This replaces the current behaviour where `onbox` silently bind-mounts the file and `netbox`/`offbox` fail mid-populate with a raw `cp` diagnostic after leaking volumes.
- A `netbox`/`offbox` creation which fails during the populate/create plan (for any cause, e.g. an unreadable source directory) no longer leaves the auto-created named volumes (worktree, gitdir and write volumes) or a partially created container on the host: the failure is reported with a `talkbox:` diagnostic and the non-zero exit status propagates.

## files to create

None. Existing files are modified:

- [lib/mounts.sh](../../../lib/mounts.sh) — the write-mode source validation.
- [lib/containers.sh](../../../lib/containers.sh) — the creation-failure rollback.
- test files listed under *tests* below.

## files to read during implementation

- [SPEC.md](../../../SPEC.md) (read-write mounts; implementation)
- [lib/mounts.sh](../../../lib/mounts.sh) (`mount_entries`, `mount_spec`, `expand_mount`)
- [lib/containers.sh](../../../lib/containers.sh) (`create_sandbox`, `run_recreate`, `plan_populate_and_create`, `execute_plan`, `stop_and_die`, `plan_volume_populate`)
- [lib/common.sh](../../../lib/common.sh) (`die`)
- [talkbox.sh](../../../talkbox.sh) (`container_action` write-mount parsing branches)
- [test/unit/mounts.bats](../../../test/unit/mounts.bats), [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats), [test/unit/containers.bats](../../../test/unit/containers.bats)
- [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats), [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats)
- the choices [placement of the write-mount folder validation](../choices/write-mount-validation-placement.gen.md) and [cleanup of auto-created volumes when container creation fails](../choices/populate-failure-volume-cleanup.gen.md)

## key internal interfaces

- `mount_entries` in `lib/mounts.sh` performs a mode-conditional check: when the mode is `write`, each resolved source must be an existing directory, otherwise it dies with a `talkbox:` message naming the source. Read-mode parsing is unchanged. Both the defaults file and the CLI specs, for all three container types and both parse branches in `container_action`, flow through this single choke point.
- The create and recreate executors in `lib/containers.sh` wrap their `execute_plan` invocation with a rollback branch: on plan failure they stop and remove the partially created container (if the plan got that far) and remove the named volumes the plan references — the worktree volume, the gitdir volume and the write volumes derived from the parsed write-mount dests — then report the failure with a `talkbox:` diagnostic, mirroring the existing `stop_and_die` pattern. The rollback removals tolerate volumes which were never created.
- A small shared helper may be introduced in `lib/containers.sh` to compute the set of volume names for a container/project/write-dests triple, so both rollback branches share it; it must not be added to `MAP.gen.md` as a separate concern if folded into the executors.

## tests

Requires tests, per the [testing](../../../SPEC.md#testing) section of the specification, via `make test-unit` and `make test-e2e`:

- unit tests (`test/unit/mounts.bats`): the write-mode directory check — a file source and a nonexistent source die with a `talkbox:` diagnostic; read-mode mounts of files remain accepted.
- unit tests (`test/unit/dispatcher.bats`, podman shim): an invalid write source produces the `talkbox:` diagnostic and no podman volume-create/populate invocations reach the shim log.
- unit tests (`test/unit/containers.bats` or a focused addition): a failing `execute_plan` in the create/recreate executors triggers the rollback removal of the named volumes and any partial container.
- end-to-end tests (`test/e2e/netbox-offbox.bats`): `netbox --write <file>` is refused with the `talkbox:` diagnostic and leaves no named volumes; a populate failure (e.g. an unreadable source directory) leaves no named volumes and no container, with a non-zero exit and `talkbox:` diagnostic.

No existing tests are superseded; the new diagnostics replace raw `cp` errors that no test asserts.
