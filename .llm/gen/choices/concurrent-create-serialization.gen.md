# Choice: Serialize the create/recreate/rm paths against concurrent invocations

## context

When two terminals invoke the same container command while the container does not yet exist, both pass `container_exists`, both run `create_sandbox`, one `podman create` fails, and its `rollback_creation_and_die` runs `podman rm -f` and `podman volume rm -f` on the shared container and volume names — which by then may belong to the *other* invocation's live container (see the issue [concurrent-create-rollback-race](../issues/concurrent-create-rollback-race.gen.md)). The same interleaving exists between `run_recreate` (which removes the container first) and any concurrent `run_container` attach, and between `run_rm_container`/`run_rm_image` and a concurrent create.

## options

### Option A: Per-container `flock` around the mutating paths (Recommended)

Acquire an exclusive `flock` on a per-user, per-container lock file (keyed by the container name, under the same runtime-dir layout as the session registry) covering the whole mutating critical section: in `run_container`, from the `container_exists` check through `create_sandbox` (including `podman start`), and in `run_recreate`, `run_rm_container` and `run_rm_image` across their `execute_plan` runs (covering `rollback_creation_and_die` as well). Concurrent invocations serialize: the loser of the create race then sees the winner's container and attaches normally; recreate/rm exclude concurrent create/attach for their duration.

- **Pros:** Eliminates the race at its cause; the loser attaches cleanly with no destructive rollback; `rollback_creation_and_die` becomes confined to this invocation's own plan by construction, so it needs no ownership tracking and the `run_recreate` caller (where removal is intentional) needs no special-casing.
- **Cons:** Introduces a locking module and a lock file layout to keep out of user-visible state; a stale lock is impossible (kernel releases `flock` when the holding process dies), but a lock directory on a non-runtime filesystem needs a per-uid location.

### Option B: Rollback ownership verification

Make `rollback_creation_and_die` verify that this invocation actually created the container/volumes before deleting them: record which plan step failed (a `podman create` failure means this invocation lost the name race and must not delete), or capture the created container ID and only delete if it matches.

- **Pros:** No locking; a direct fix to the destructive failure mode.
- **Cons:** Fragile step-index/ID bookkeeping; the check-then-delete is itself racy; does nothing about two invocations racing on the `podman start`/`setup.sh` tail or a concurrent `--recontain`/`--rm-container` racing a create; the `run_recreate` caller, where removal is intentional, must still be distinguished.

### Option C: Both A and B

Serialize with `flock` and add rollback ownership verification as defense in depth.

- **Pros:** Belt and braces.
- **Cons:** The ownership verification is dead weight once the lock holds; every rollback failure under the lock only ever targets this invocation's own plan output, so the extra layer adds complexity without a reachable failure mode.

## recommendation

**Option A.** The lock removes the race itself, which makes the rollback safe by construction and needs no caller distinction. Locking `run_recreate` and the removal verbs under the same lock also closes the adjacent races (recreate/rm interleaved with create or attach).

## selected option

**Option A** (selected by the user).
