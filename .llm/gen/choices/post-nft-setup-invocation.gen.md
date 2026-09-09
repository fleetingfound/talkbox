# Choice: Post-nft entrypoint setup invocation mechanism

## Context

[Review: entrypoint-before-nft ordering](../reviews/entrypoint-before-nft-ordering.gen.md)
Option B recommends moving the entrypoint setup (dotfiles copy, git identity
writes, gitdir init, `git fetch host`/`git reset`) out of the image `ENTRYPOINT`
and into a host-driven `podman exec` that runs **after**
`install_nft_deny_or_die`, so the trusted setup path runs under the nft deny
list rather than in the pre-nft window. This is the follow-on to
[Phase 14b](../plans/phase-14b-entrypoint-readonly-bindmount.gen.md) (Option F,
which closes the *tampering* vector) and closes the *ordering* vector for the
trusted entrypoint body itself.

Today the image `ENTRYPOINT` is
[`/usr/local/bin/entrypoint.sh`](../../../image/entrypoint.sh) (set in
[image/Containerfile](../../../image/Containerfile) L35). The three persistent
planners ([`lib/containers.sh`](../../../lib/containers.sh) `plan_onbox` L107,
`plan_netbox` L402, `plan_offbox` L454) pass `sleep infinity` as the command,
so `entrypoint.sh` runs setup on `podman start` then `exec bash -c "sleep
infinity"`. The executors order `podman start` → `wait_for_entrypoint` (sentinel
poll) → `install_nft_deny_or_die` → `podman exec` user command
([`lib/containers.sh`](../../../lib/containers.sh) `run_onbox` L229-231,
`run_netbox` L694-696).

The one-shot `podman run --rm` paths (`plan_volume_populate` L339-351,
`container_sync_cmd` non-running path L866-877) rely on the image `ENTRYPOINT`
running setup then `exec`-ing the supplied command. These run with
`--network=none`, so the pre-nft ordering concern does not apply to them; they
should keep working without invasive change.

`SPEC.md` L196 states: "Whenever one of these containers starts, the script
`entrypoint.sh` copies these into `/home/dev/`." and L198: "The script
`entrypoint.sh` is on `PATH` inside the containers so that the user can call it
manually." Both must remain satisfied (the manual-availability contract is
preserved by all options below; the "whenever one of these containers starts"
wording is updated to reflect that setup now runs via exec after the deny list
is enforced).

The chosen mechanism must:
- prevent `entrypoint.sh` (or its setup body) from running on `podman start`
  of a persistent container, so the executor can install nft first;
- run the setup body synchronously via `podman exec` after
  `install_nft_deny_or_die`, before the user command;
- leave one-shot `podman run --rm` containers functional;
- keep `entrypoint.sh` on `PATH` for manual use per SPEC.

## Options

### Option A — Override `--entrypoint` for persistent containers; invoke `entrypoint.sh` via exec post-nft with a no-op command (Recommended)

Keep `entrypoint.sh` and the image `ENTRYPOINT` unchanged. Add an
`--entrypoint=sleep` override (with `infinity` already as the command arg) to
the three persistent planners so PID 1 is `sleep infinity` directly and
`entrypoint.sh` does **not** run on `podman start`. After
`install_nft_deny_or_die`, the executor runs
`podman exec "$ctr" entrypoint.sh true` — `entrypoint.sh` performs its full
setup body, then `exec bash -c "true"` exits 0; the setup side effects (copied
dotfiles, git config, gitdir init) persist in the container filesystem.

The no-op-command pattern (`entrypoint.sh true`) is exactly how one-shot
containers already work (they pass a real command that `entrypoint.sh` execs
after setup), so no `entrypoint.sh` modification is needed. The tmpfs
`/run/talkbox` mount, the sentinel write, and `wait_for_entrypoint` are removed
(setup is now synchronous, so the readiness poll is obsolete); the sentinel
write line in `entrypoint.sh` is left in place (harmless when invoked manually
or by one-shot containers) or removed as a minor cleanup.

One-shot paths (`plan_volume_populate`, `container_sync_cmd` non-running path)
are unchanged: they use the image `ENTRYPOINT` (`entrypoint.sh`) with their
command, run `--network=none`, and are not subject to the ordering concern.

**Pros:**
- Smallest possible change: one `--entrypoint` flag per persistent planner, one
  `podman exec entrypoint.sh true` line per executor, removal of
  `wait_for_entrypoint` calls and the tmpfs mount.
- No `entrypoint.sh` modification and no new files — reuses the existing script
  verbatim via the already-established no-op-command convention.
- One-shot containers are untouched.
- `entrypoint.sh` remains on `PATH` and as the image `ENTRYPOINT` (for one-shot
  and manual use), satisfying SPEC L198 without change.

**Cons:**
- The "setup runs via `entrypoint.sh true`" invocation is slightly implicit
  (relies on the reader understanding that `exec bash -c "true"` exits after
  setup). A comment at the exec site mitigates this.
- `entrypoint.sh` retains the sentinel-write line, which is now dead code for
  persistent containers (harmless, but a small wart).

### Option B — Extract setup into `image/setup.sh`; make the image ENTRYPOINT trivial

Add a new `image/setup.sh` containing the dotfiles/git/sentinel body. Change
the image `ENTRYPOINT` to `exec sleep infinity` (trivial) — or remove it and
let the planner-supplied `sleep infinity` command be PID 1 directly. Persistent
containers: the trivial ENTRYPOINT runs `sleep infinity` on start, the executor
runs `podman exec "$ctr" setup.sh` post-nft. One-shot containers must be
changed to invoke `setup.sh` then their command explicitly (e.g.
`podman run ... <image> bash -c "setup.sh && exec <command>"`), since the
ENTRYPOINT no longer runs setup.

**Pros:**
- Cleanest separation of concerns: setup is a named, single-purpose script.
- No implicit no-op-command convention.

**Cons:**
- New file (`image/setup.sh`) and duplication risk (setup logic split from
  `entrypoint.sh`, which still exists on `PATH` for manual use per SPEC — two
  scripts with overlapping bodies, or `entrypoint.sh` becomes a thin wrapper
  calling `setup.sh`).
- One-shot paths (`plan_volume_populate`, `container_sync_cmd`) must be
  reworked to invoke `setup.sh` explicitly, increasing blast radius.
- Larger SPEC/image contract change.

### Option C — Add a `--setup-only` mode to `entrypoint.sh`; override `--entrypoint` for persistent containers

Add a flag/env-var to `entrypoint.sh` (e.g. `TALKBOX_SETUP_ONLY=1` or
`--setup-only`) that, when set, performs setup and `exit 0`s without the
`exec bash -c "$*"` / `exec /bin/bash` tail. Persistent containers override
`--entrypoint=sleep` (so `entrypoint.sh` does not run on start); the executor
runs `podman exec -e TALKBOX_SETUP_ONLY=1 "$ctr" entrypoint.sh` post-nft.
One-shot containers invoke `entrypoint.sh` normally (no flag), unchanged.

**Pros:**
- Explicit, self-documenting setup-only mode (no reliance on the no-op-command
  convention).
- One-shot containers unchanged (same as Option A).
- Single script (no new file).

**Cons:**
- Modifies `entrypoint.sh` (adds a mode branch), where Option A modifies
  nothing in the script.
- The flag is a new surface that must be documented and maintained.

## Recommendation

**Option A** was recommended as the most localised change (see above), but
**Option B** is a valid alternative prioritising clean separation of concerns
over minimal blast radius.

## Selected option

**Option B — Extract setup into `image/setup.sh`; make the image ENTRYPOINT
trivial.** Selected by the user.

A new `image/setup.sh` contains the dotfiles-copy, git-identity-write, and
gitdir-init (`git init`/`git fetch host`/`git reset --mixed`) body. The image
`ENTRYPOINT` is removed (or made trivial) so that the planner-supplied `sleep
infinity` command is PID 1 directly for persistent containers; `entrypoint.sh`
remains in the image (on `PATH` per SPEC L198) as a thin wrapper that sources
or invokes `setup.sh` then `exec`s the supplied command — preserving one-shot
`podman run --rm` behaviour and manual use. The persistent executors run
`podman exec "$ctr" setup.sh` (or the wrapper) **after**
`install_nft_deny_or_die`, before the user command. One-shot paths
(`plan_volume_populate`, `container_sync_cmd` non-running path) are updated to
invoke setup explicitly (e.g. `bash -c "setup.sh && exec <command>"`) since the
ENTRYPOINT no longer runs setup automatically. The tmpfs `/run/talkbox` mount,
the sentinel write, and `wait_for_entrypoint` are removed (setup is now
synchronous). `SPEC.md` L196 is updated to reflect that setup runs via exec
after the deny list is enforced for persistent containers.

## Related

- [Review: entrypoint-before-nft ordering and agent-modified entrypoint risk](../reviews/entrypoint-before-nft-ordering.gen.md)
- [Issue: agent-modified entrypoint runs before nft deny enforcement](../issues/agent-modified-entrypoint-pre-nft.gen.md)
- [Choice: Entrypoint readiness synchronization mechanism](entrypoint-readiness-sync.gen.md) — the prior choice (Option A, tmpfs sentinel) whose mechanism is obsoleted by this refactor for persistent containers.
- [Phase 14b: read-only bind-mount the entrypoint](../plans/phase-14b-entrypoint-readonly-bindmount.gen.md)
