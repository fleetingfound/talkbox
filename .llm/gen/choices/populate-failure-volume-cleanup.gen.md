# Choice: Cleanup of auto-created volumes when container creation fails

## context

For `netbox`/`offbox`, the populate steps in `create_sandbox` run no-network temporary containers whose `-v <volume>:/talkbox/target` flags cause podman to auto-create the named worktree, gitdir and write volumes. When a populate copy fails mid-plan (`execute_plan` returns non-zero), the auto-created volumes remain on the host while no container exists (see the issue [write-mount-file-source-unvalidated](../issues/write-mount-file-source-unvalidated.gen.md)). Early write-mount source validation removes the most common trigger, but other populate failures (e.g. an unreadable source directory) can still leak volumes.

## options

### Option A: Executor rollback (Recommended)

In the create and recreate executors in [lib/containers.sh](../../../lib/containers.sh), wrap the `execute_plan` invocation so that on failure the named volumes the plan referenced (the worktree, gitdir and write volumes for the project/container pair) are removed, a partially created container is stopped and removed, and a `talkbox:` diagnostic reports the failure before propagating the exit status.

- **Pros:** Guarantees a failed creation leaves no orphaned named volumes or half-created container regardless of the failure cause; the volume set is fully derivable from the project slug and the parsed write mounts; consistent with the existing `stop_and_die` pattern.
- **Cons:** Adds a failure branch to the executors; rollback best-effort removals must tolerate volumes podman never got to create.

### Option B: Explicit volume pre-creation

Emit explicit `podman volume create` steps at the head of the plan and make a failed `execute_plan` remove the created volumes.

- **Pros:** Same end state; volume creation becomes visible in the plan.
- **Cons:** Changes the plan model (new command kind in every populate path) without changing the failure semantics — the rollback branch is still needed.

### Option C: Validation only

Rely on the early write-mount source validation and accept that other populate failures may still leak volumes.

- **Pros:** No executor change.
- **Cons:** Leaves the general hygiene gap open (unreadable sources, disk-full, image pull failures mid-plan).

## recommendation

**Option A.** It closes the leak for every failure cause with a single failure branch in the executors, without altering the successful-path plan model.

## selected option

**Option A** (selected by the user). The create/recreate executors roll back created volumes and any partially created container when `execute_plan` fails.
