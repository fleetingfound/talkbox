# Phase 28b: serialize the create/recreate/rm paths with a per-container lock

Status: `SUCCESS`

Implements [the plan](../plans/phase-28b-concurrent-create-race-lock.gen.md), which resolves [the concurrent-create-rollback-race issue](../issues/concurrent-create-rollback-race.gen.md) (marked complete): [lib/locking.sh](../../../lib/locking.sh) (new) provides the per-container exclusive-lock helper — `talkbox_lock_dir` (`$TALKBOX_LOCK_DIR` override, else `$XDG_RUNTIME_DIR/talkbox/locks`, else a per-uid `${TMPDIR:-/tmp}/talkbox-locks-<uid>` fallback), `container_lock_path`, and `acquire_container_lock`/`release_container_lock` bracketing a critical section with a blocking fd-based `flock` on a dynamically allocated shell fd (released by kernel `flock` semantics on process death, so a killed invocation leaves no stale lock) — and [lib/containers.sh](../../../lib/containers.sh) now sources it and holds the lock around each mutating critical section: `run_container` from its `container_exists` check through `create_sandbox` and `podman start` (releasing before the nft/setup/exec tail, so concurrent attach sessions proceed in parallel), and the whole `execute_plan` including the `rollback_creation_and_die` failure path for `run_recreate`, `run_rm_container` and `run_rm_image`, so simultaneous invocations serialize — the loser of a create race attaches to the winner's container instead of destroying it through its rollback.

## Key design finding

The lock fd must not reach long-lived daemon descendants: conmon (forked by `podman start`) inherits the shell's open file descriptors, and an inherited fd keeps the `flock` held on the shared open-file-description even after `release_container_lock` closes the shell's copy (verified empirically against the installed podman: the lock stayed held for the container's lifetime). `run_without_lock_fd` in [lib/locking.sh](../../../lib/locking.sh) handles this: it runs a command in a subshell with the lock fd closed, so conmon and pasta never inherit it and the release stays synchronous. `execute_plan` routes every plan command through it, as does `run_container`'s direct `podman start` step, preserving command output and exit-status semantics exactly.

## Changes

- [lib/locking.sh](../../../lib/locking.sh) (new): the lock helper module described above.
- [lib/containers.sh](../../../lib/containers.sh): `source lib/locking.sh`; `acquire_container_lock`/`release_container_lock` around the four mutating cores; `execute_plan` and the `run_container` start step run podman commands via `run_without_lock_fd`; `rollback_creation_and_die` and all externally observable behaviour unchanged.
- [MAP.gen.md](../../../MAP.gen.md): new `lib/locking.sh` entry; the `lib/containers.sh` entry now describes the serialized lifecycle and the fd-closed execution.
- No changes to `test/` (the red-phase tests for this phase were pre-committed in 79934d4).

## Verification

- `make lint` and `shfmt -d` clean.
- `make test-unit`: 323/323, including the nine new lock tests (exclusivity/blocking, lock-dir layout, release on holder death, held-across exists-check/create/start with an unlocked exec tail, rollback under a failed create, and the recreate/rm-container/rm-image plan coverage).
- `make test-e2e`: 85/85, including the two new concurrency tests (two simultaneous first invocations both succeed against one created container with no rollback line; a concurrent `--rm-container` serializes behind the create's critical section instead of interleaving with it).

## Linked documents

- Plan: [phase-28b-concurrent-create-race-lock.gen.md](../plans/phase-28b-concurrent-create-race-lock.gen.md) — marked complete in the plans index.
- Issue resolved: [concurrent-create-rollback-race.gen.md](../issues/concurrent-create-rollback-race.gen.md) — marked complete; the per-container lock makes the create-vs-create rollback destruction unreachable by construction.
- No dispute document (no test or helper was found misspecified) and no new issue documents.
