# Build: Phase 23a — write-mount folder validation and failed-creation volume rollback

Status: **SUCCESS** (all 312 unit tests and all 74 e2e tests pass).

Implements [Phase 23a](../plans/phase-23a-write-mount-validation-and-rollback.gen.md), which resolves the [write-mount-file-source-unvalidated issue](../issues/write-mount-file-source-unvalidated.gen.md). No verdict document was provided; the implementation follows the two selected choices [write-mount-validation-placement](../choices/write-mount-validation-placement.gen.md) (Option A: validate inside `mount_entries`) and [populate-failure-volume-cleanup](../choices/populate-failure-volume-cleanup.gen.md) (Option A: executor rollback). The twelve red tests written for the phase pass unmodified.

## Changes

### [lib/mounts.sh](../../../lib/mounts.sh) — write-mode source validation

- New `require_write_dir <mode> <src>` helper: when the mode is `write` and the expanded source is not an existing directory, `die`s with `talkbox: write mount source is not a directory: <src>` (exit 1). Read-mode parsing is untouched.
- `mount_entries` calls it for every parsed spec — both the `defaults/write.mounts` lines and the CLI `--write` specs — right after `expand_mount`, so the check is the single choke point for all three container types and both parse branches in `container_action`, failing before any podman state is created.

### [lib/containers.sh](../../../lib/containers.sh) — plan-failure rollback

- `execute_plan` now stops at the first failing plan command and returns its status (`"${cmd[@]}" || return $?`); previously it relied on `set -e` aborting the whole script mid-plan, which left the auto-created volumes behind and bypassed any failure handling. The rm-container/rm-image paths keep their net behaviour (non-zero still propagates).
- New `container_volumes <out> <container> <project> <dsts>` helper computes the volume-name set for a container/project/write-dests triple (worktree + gitdir + per-dest write volumes for netbox/offbox, gitdir only for onbox); `plan_container_volumes_rm` is refactored to emit its `podman volume rm -f` steps from this shared list.
- New `rollback_creation_and_die <container> <project> <dsts>` mirrors `stop_and_die`: it stops the container, `podman rm -f`s it (best-effort, tolerating a container that was never created), removes each existing volume from the `container_volumes` set, then `die`s with `talkbox: cannot create container <ctr>; rolled back the partial container and volumes` (exit 1).
- `create_sandbox` and `run_recreate` wrap their `execute_plan` invocation in `if ! ...; then rollback_creation_and_die "$container" "$project" "$4"; fi`, so a failing populate/create/start plan leaves no orphaned named volumes and no partially created container.

## Verification

- `make lint` and `make format` clean over the modified files.
- `make test-unit`: total=312 pass=312 fail=0 (previously the ten new unit tests failed at their designed assertions).
- `make test-e2e`: total=74 pass=74 fail=0 (previously the two new e2e tests failed at the missing `talkbox:` diagnostic).
