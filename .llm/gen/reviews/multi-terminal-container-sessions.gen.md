# Review: Multiple terminals attached to the same container

## Question

Does talkbox support having the same `onbox` container open in multiple terminals simultaneously, and similarly for `netbox` and `offbox`?

## Short answer

**Mechanically possible, but not supported.** All three commands share one code path (`run_container` in [lib/containers.sh](lib/containers.sh)), so the behavior is identical for `onbox`, `netbox` and `offbox`. A second terminal can attach to the same persistent container and get a working shell, but the lifecycle is designed around one session at a time: **whichever session exits first stops the entire container, killing all other concurrent sessions**. Two related hazards (a destructive first-invocation race and side effects of re-running `setup.sh` under a live session) make concurrent use fragile in other ways as well.

## How a second terminal attaches

When `onbox`/`netbox`/`offbox` is invoked and the named container already exists, [lib/containers.sh](lib/containers.sh) `run_container`:

1. Skips creation (`container_exists` check).
2. Runs `podman start` — a no-op returning 0 on an already-running container (verified experimentally).
3. Re-applies the nft deny ruleset for `onbox`/`netbox` (skipped for `offbox`, which has no nft step) — verified idempotent: `nft add table`/`add set`/`add chain` succeed on re-application, so the second terminal does not trip `install_nft_deny_or_die` (which would otherwise stop the container). One cosmetic artifact: `add rule` *appends*, so each invocation while the container is running adds a duplicate accept/drop rule pair to the `talkbox_deny` output chain. Functionally equivalent, bounded by the number of invocations within one running period (rules are flushed when pasta recreates the netns on the next `podman start`).
4. Re-runs `setup.sh` via `podman exec` (see [Concurrent re-invocation side effects](#concurrent-re-invocation-side-effects) below).
5. Execs a fresh shell (`podman exec -it … /bin/bash`) into the same container.

So two terminals do end up with two shells in one container, sharing the same worktree/gitdir volumes and the same pasta network namespace. The `.bashrc` banner sentinel (`_TALKBOX_BANNER_SHOWN`) is per-shell, so each terminal gets its own banner. Ordinary git `index.lock` contention between the two shells is standard multi-shell git behavior, not a talkbox defect.

Notably, *host-side* git operations against a live container are explicitly supported: `run_sync`/`container_sync_cmd` in [lib/containers.sh](lib/containers.sh) has a dedicated running-container branch (`podman exec` into the live container) and does **not** stop it afterwards. So running `onbox sync` from a third terminal while sessions are open is fine — the problem is exclusively with `run_container`'s exec-then-stop tail.

## The teardown problem

`exec_in_container` in [lib/containers.sh](lib/containers.sh) calls `stop_container` unconditionally after its exec session exits (`podman stop -t 5`). Stopping the container terminates every other exec session in it. Verified empirically: an exec session mid-command exited with status 255 when the container was stopped after a second, short-lived exec finished.

Consequences:

- Terminal A (interactive shell, possibly a coding agent mid-task) and terminal B (even a brief `onbox -c 'ls'`) can coexist only until B's command returns — then the container stops, SIGTERM/SIGKILLs A's shell after the 5-second grace period, and any in-flight work in A is lost.
- A git operation in session A that is mid-write when the SIGKILL lands can leave a stale `index.lock` behind.
- The container persists (created state) and can be restarted by the next invocation, so no on-disk volume/gitdir data is lost — only the live sessions and their in-flight processes.

This is the core reason multi-terminal use must be considered unsupported: it works right up until any one terminal exits. See [Issue: concurrent session exit stops the container](../issues/concurrent-session-exit-stops-container.gen.md).

## Concurrent re-invocation side effects

Even before the teardown, opening the second terminal perturbs the first:

- `run_setup_in_container` re-runs [image/setup.sh](image/setup.sh) on every invocation (per spec). Its `cp -a` of the dotfiles into `/home/dev` overwrites files, so any in-session edits to dotfiles (e.g. a modified `~/.bashrc` in container A) are clobbered the moment terminal B opens.
- `include_host_modules` does `chmod -R u+w` + `rm -rf` + re-copy of `<worktree>/.git/modules` and toggles write permissions on module `objects`/`refs`. If session A is mid git operation (e.g. `git status` on a repo with submodules) while session B's setup.sh runs, transient git errors are possible.
- These are spec-mandated per-invocation steps; they are only hazards under concurrency.

## Options asymmetry between concurrent terminals

Mounts (`--read`/`--write`) and pasta ports are baked into the container at creation. When a second terminal passes different `--read`/`--write`/`--port` values against an existing container, they are silently ignored (the args are assembled but never applied to a container that is not created). The `--deny-ip`/`--allow-ip` sets, by contrast, *are* re-applied to the nft ruleset on every invocation, so terminal B can silently change the network policy seen by terminal A. With concurrent terminals, the first terminal's create-time options win for mounts and ports, and the last invocation's deny/allow sets win for nft.

## First-invocation race

If two terminals invoke the same command simultaneously while the container does not yet exist, both pass the `container_exists` check and both attempt `podman create` with the same name. The loser's `rollback_creation_and_die` then runs `podman rm -f` on the shared container name plus `podman volume rm` on the shared volume names — which at that point may refer to the *winner's* successfully created container and its freshly created volumes (including the gitdir volume holding the container's git history), potentially killing the winner's live session and deleting its history. See [Issue: concurrent create rollback race](../issues/concurrent-create-rollback-race.gen.md).

## Test coverage

No unit or e2e test exercises two concurrent sessions. E2e coverage is sequential reuse only:

- `onbox creates a persistent container that survives after the shell exits` ([test/e2e/lifecycle.bats](test/e2e/lifecycle.bats))
- `onbox -c <command> runs within the same persistent container` (sequential `podman exec` reuse)

A natural test for the desired behavior (session A sleeping in a background exec; session B running `-c --noninteractive true`; assert A survives) would currently fail at the teardown step.

## What a fix would look like

The minimal change is in `exec_in_container` ([lib/containers.sh](lib/containers.sh)): record whether the container was already running when this invocation began (`container_running` before `podman start`), and only call `stop_container` if this invocation started it from a stopped state. That preserves the current sequential lifecycle (create → start → exec → stop → later invocations restart) while letting concurrent sessions coexist, with the container remaining running until its owning session exits. The creation race needs a separate guard (see the issue document).

## Verdict

- **Sequential reuse of a persistent container: fully supported and tested.**
- **Concurrent multi-terminal attach: works mechanically, but is unsupported and unsafe in practice** — the first exit tears down all other sessions, the second invocation re-runs `setup.sh` under the live first session, and simultaneous first invocations can destroy each other's containers.
