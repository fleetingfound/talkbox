# Phase 14c: Install nft ruleset before entrypoint setup runs

#flow/redgreen #model/default

## Summary

Refactors the persistent-container startup sequence so that
`install_nft_deny_or_die` runs **before** the entrypoint setup body
(dotfiles copy, git identity writes, gitdir `git init`/`git fetch host`/`git
reset --mixed`), closing the pre-nft window for the trusted entrypoint itself
(Option B of
[review: entrypoint-before-nft ordering](../reviews/entrypoint-before-nft-ordering.gen.md)).
The design selected for this phase is to extract the setup body into a new
`image/setup.sh`, remove the image `ENTRYPOINT` (the planner-supplied `sleep
infinity` command becomes PID 1 directly for persistent containers), and have
the executors run `setup.sh` via `podman exec` **after**
`install_nft_deny_or_die`. The existing tmpfs `/run/talkbox` sentinel
mechanism and `wait_for_entrypoint` poll are removed (setup is now
synchronous). One-shot `podman run --rm` paths are updated to invoke
`setup.sh` explicitly before their command. This is the second of two phases
resolving
[issue: agent-modified entrypoint runs before nft deny enforcement](../issues/agent-modified-entrypoint-pre-nft.gen.md);
it builds on [Phase 14b](phase-14b-entrypoint-readonly-bindmount.gen.md),
which closed the tampering vector.

The new persistent-container startup ordering becomes:

1. `podman start "$ctr"` — PID 1 is `sleep infinity` (trivial; no setup runs).
2. `install_nft_deny_or_die "$ctr" ...` — deny/allow ruleset applied to the
   container netns.
3. `podman exec "$ctr" setup.sh` — dotfiles, git identity, gitdir init run
   **under** the deny list.
4. `podman exec` the user command.

## Design rationale

The setup invocation mechanism must: prevent any setup code from running on
`podman start` of a persistent container (so the executor can install nft
first); run the setup body synchronously via `podman exec` after
`install_nft_deny_or_die`, before the user command; leave one-shot
`podman run --rm` containers functional; and make `image/setup.sh` the sole
setup script (the former `entrypoint.sh` is deleted, and the SPEC contract
that placed it on `PATH` has been removed).

The selected design extracts the setup body into `image/setup.sh` and removes
the image `ENTRYPOINT` so the planner-supplied `sleep infinity` is PID 1
directly for persistent containers. This was chosen over the alternative of
overriding `--entrypoint` per persistent planner and re-invoking the existing
`entrypoint.sh` via exec (which would have left `entrypoint.sh` in place as a
combined setup-and-exec script) because it gives setup a named,
single-purpose script with a clean separation of concerns, at the cost of
updating the one-shot paths to invoke `setup.sh` explicitly.

The prior design for entrypoint readiness synchronization (a tmpfs `/run/talkbox`
sentinel written by the entrypoint and polled by `wait_for_entrypoint`) is
superseded for persistent containers by this refactor: the sentinel/poll
mechanism is removed because setup is now synchronous.

## Aspects of the specification implemented

`SPEC.md` has been updated to agree with this phase's design; the implementation
must conform to the updated wording.

- `SPEC.md` L196 — now states that after a container has been started,
  `image/setup.sh` is invoked with `podman exec` to install the dotfiles, and
  for `onbox`/`netbox` this happens after `nft` has been configured. The
  dotfiles-copy behaviour and project-overrides-global precedence are unchanged.
- `SPEC.md` L198 — the prior sentence "The script `entrypoint.sh` is on `PATH`
  inside the containers so that the user can call it manually" has been
  **removed**. `entrypoint.sh` is no longer part of the documented contract;
  `image/setup.sh` is the sole setup script, and `image/entrypoint.sh` is
  deleted by this phase.
- `SPEC.md` network section — now states that for `onbox`/`netbox` the
  restrictions are enforced via `nft` before `image/setup.sh` is invoked,
  codifying the ordering invariant this phase implements.
- `SPEC.md` Containerfile section — now lists `image/setup.sh` (installation of
  dotfiles, configuration of git identity, initialisation of the container's git
  directory) in place of the former `entrypoint.sh` entry.

## Aspects deferred

- Narrowing `NOPASSWD:ALL` sudo to the minimum needed (Option C of the review)
  is deferred; the broad sudo remains. This is independently desirable but
  orthogonal to the ordering fix.
- Pre-created netns (Option A / Option D of
  [ip-deny-allow-enforcement](../choices/ip-deny-allow-enforcement.gen.md)),
  which would make the ordering invariant structural (rules present before any
  container code runs), is deferred.
- The host-side source tampering surface when talkbox itself is the working repo
  (narrow case, documented in the review) is not addressed here; Phase 14b's
  read-only bind mount is the partial mitigation for that case.

## External-facing functionality

- No change to the user-visible container behaviour for the trusted path:
  dotfiles are applied, git identity is configured, the gitdir is initialised,
  and the user command runs — all as before. The only observable difference is
  internal ordering (setup now runs after nft, synchronously, rather than on
  start).
- `onbox`/`netbox` (and their `--recontain`/`--rebuild` verbs) started with a
  non-empty deny set now have the deny list enforced before setup runs, closing
  the pre-nft window for the trusted entrypoint body. A buggy or
  indirectly-triggered setup step (e.g. a planted `.bashrc`, a git hook in the
  gitdir volume) can no longer make outbound connections to denied IPs during
  setup.
- `offbox` is unaffected (it does not call `install_nft_deny`); its setup also
  moves to a post-start `podman exec` for consistency, but with no nft step.
- One-shot `podman run --rm` paths (`plan_volume_populate`,
  `container_sync_cmd` non-running path) continue to apply dotfiles/git setup
  before their command, now by invoking `setup.sh` explicitly; they run
  `--network=none` so the ordering concern does not apply.

## Files to be created

- [`image/setup.sh`](../../../image/setup.sh) — the setup body extracted from
  [`image/entrypoint.sh`](../../../image/entrypoint.sh): the dotfiles-copy
  block (global then project), the git-identity global-config writes, and the
  gitdir-init block (`git init`, `remote add`/`set-url host /host/git/`,
  `git fetch host`, `git reset --mixed`). Mode `0755`. Installed into the image
  by a new `COPY` in the Containerfile (replacing the former `entrypoint.sh`
  `COPY`), and also reachable at runtime via the Phase 14b read-only bind mount
  convention if desired (or via the image layer). The script exits 0 on
  completion (no `exec`).

## Files to be modified

- [`image/entrypoint.sh`](../../../image/entrypoint.sh) — **deleted**. Its
  setup body moves to `image/setup.sh`; the `exec` tail and the sentinel-write
  block (`/run/talkbox/ready`) are removed with it. The image no longer
  references `entrypoint.sh` (no `COPY`, no `ENTRYPOINT`), matching the updated
  SPEC which dropped the "entrypoint.sh on PATH" contract. One-shot and manual
  use now invoke `setup.sh` directly.
- [`image/Containerfile`](../../../image/Containerfile) — replace the
  `COPY` of `entrypoint.sh` (L25) with `COPY --chmod=755 setup.sh
  /usr/local/bin/setup.sh`. Remove the `ENTRYPOINT
  ["/usr/local/bin/entrypoint.sh"]` directive (L35) so that the
  planner-supplied command (`sleep infinity`) is PID 1 directly for persistent
  containers, and one-shot containers invoke their command (with setup) via
  the explicit `setup.sh && <command>` pattern in their plan. The image thus
  has no `ENTRYPOINT` and no `entrypoint.sh`.
- [`lib/containers.sh`](../../../lib/containers.sh) —
  - The three persistent planners (`plan_onbox` L59-108, `plan_netbox` L353-403,
    `plan_offbox` L405-455): remove the `--tmpfs /run/talkbox` entries (the
    sentinel is obsolete). No `--entrypoint` override is needed since the image
    no longer has a non-trivial `ENTRYPOINT`; the existing `sleep infinity`
    command arg becomes PID 1 directly.
  - `wait_for_entrypoint` (L188-193): remove (no longer called). The
    `podman exec`-based sentinel poll is obsolete.
  - The executors `run_onbox` (L215-244), `run_netbox` (L685-709), `run_offbox`
    (L711-734): reorder to `podman start` → `install_nft_deny_or_die` (onbox/netbox
    only) → `podman exec "$ctr" setup.sh` → `podman exec` user command. Remove
    the `wait_for_entrypoint` call. The `setup.sh` exec must succeed (non-zero
    exit stops the container and raises a `talkbox:` error, mirroring the
    `install_nft_deny_or_die` pattern).
  - `run_netbox_recontain` (L736-751), `run_netbox_rebuild` (L769-781): reorder
    to run `setup.sh` via exec after `install_nft_deny_or_die` (these verbs
    start the container via `execute_plan` then install nft; setup exec is
    inserted between nft and the final `podman stop`). Note: these verbs do not
    run a user command (they stop after start+nft); they should still run
    `setup.sh` so the committed/inherited state is initialised before the next
    `run_netbox` reuses the container. Confirm against the existing intent.
  - `run_offbox_recontain` (L753-767), `run_offbox_rebuild` (L783-794): insert
    `setup.sh` exec after `podman start` (no nft step for offbox).
  - `plan_volume_populate` (L339-351): update the one-shot command so setup runs
    before the `cp -a` — e.g. the command becomes `bash -c "setup.sh && cp -a
    /talkbox/source/. /talkbox/target/"` (or `setup.sh; exec cp ...`). These
    run `--network=none` so ordering is not a concern, but setup (dotfiles) is
    not strictly needed for a `cp` operation; the implementing agent should
    confirm whether `plan_volume_populate` actually needs setup at all (it
    copies host content into a volume and likely does not need dotfiles/git
    init) — if not, leave it unchanged and only update `container_sync_cmd`.
  - `container_sync_cmd` (L854-878) non-running path (L866-877): update the
    one-shot command so `setup.sh` runs before the sync script, since git
    transport relies on the gitdir being initialised. The command becomes
    `bash -c "setup.sh && exec bash -c '$script' _ <branches>"` or equivalent.

## Relevant files to read during implementation

- [`image/entrypoint.sh`](../../../image/entrypoint.sh) — the setup body to
  extract (L4-34) before deleting the file.
- [`image/Containerfile`](../../../image/Containerfile) — L25 (`COPY
  entrypoint.sh`), L35 (`ENTRYPOINT`).
- [`lib/containers.sh`](../../../lib/containers.sh) — the planners and executors
  cited above; `wait_for_entrypoint` (L188-193); `install_nft_deny_or_die`
  (L207-213); the existing `--tmpfs /run/talkbox` entries (L79, L374, L426).
- [`lib/network.sh`](../../../lib/network.sh) — `install_nft_deny` (L139-171),
  unchanged by this phase.
- [`SPEC.md`](../../../SPEC.md) — L196-198 (dotfiles / entrypoint contract to
  update).
- [`test/unit/containers.bats`](../../../test/unit/containers.bats) — existing
  tmpfs/sentinel tests (L338-369) and `wait_for_entrypoint` tests (L372-401)
  that will be removed/rewritten.
- [`test/unit/netbox-offbox.bats`](../../../test/unit/netbox-offbox.bats) —
  existing tmpfs-propagation tests (L455-524) to remove/rewrite.
- [`test/e2e/git-identity.bats`](../../../test/e2e/git-identity.bats) —
  references `/run/talkbox/ready` (L72) in an existing e2e; will need updating.
- [`test/e2e/onbox.bats`](../../../test/e2e/onbox.bats),
  [`test/e2e/deny-allow.bats`](../../../test/e2e/deny-allow.bats) — e2e patterns
  for the new ordering.
- [`.llm/gen/choices/entrypoint-readiness-sync.gen.md`](../choices/entrypoint-readiness-sync.gen.md)
  — the superseded choice.
- [`.llm/gen/plans/phase-11a-entrypoint-readiness-sync.gen.md`](phase-11a-entrypoint-readiness-sync.gen.md)
  — the prior phase that introduced the sentinel; its tests are now superseded.

## Key internal interfaces

- `image/setup.sh` (new) — no arguments; performs dotfiles copy, git identity
  writes, gitdir init; exits 0 on success, non-zero on failure. Idempotent
  (safe to re-run, as the current entrypoint body already is: `git init` is
  guarded by `rev-parse`, `remote add`/`set-url` is conditional).
- `image/entrypoint.sh` — deleted; its setup body moves to `setup.sh`. The
  image has no `ENTRYPOINT` and no `entrypoint.sh`.
- The persistent executors' startup contract changes from
  `podman start` → `wait_for_entrypoint` → `install_nft_deny_or_die` → `podman exec`
  to
  `podman start` → `install_nft_deny_or_die` → `podman exec setup.sh` → `podman exec`
  (onbox/netbox); offbox omits the nft step.
- `wait_for_entrypoint` — removed (obsolete).
- The `--tmpfs /run/talkbox` planner entries — removed (obsolete).
- `SPEC.md` L196 / network section — already updated to describe post-start,
  post-deny-list setup via `image/setup.sh` for persistent containers; the
  implementation conforms.

## Tests

This phase requires tests. It is a redgreen phase: the first subagent rewrites
the existing sentinel/tmpfs tests (which are now inconsistent with the new
synchronous-setup ordering) into failing tests for the new behaviour; the
second implements the refactor so all tests pass.

### Unit tests — `test/unit/containers.bats`, `test/unit/netbox-offbox.bats`

- Remove (or rewrite) the existing tmpfs-mount tests
  (`containers.bats:338-369` "onbox/netbox/offbox plan mounts a tmpfs at
  /run/talkbox …" and the recontain/rebuild tmpfs-propagation tests) — the tmpfs
  is removed. Replace with assertions that the three persistent planners **do
  not** emit a `--tmpfs /run/talkbox` entry.
- Remove (or rewrite) the `wait_for_entrypoint` tests
  (`containers.bats:372-401`) — the function is removed. If a new
  `run_setup_in_container`-style helper is introduced, add unit tests for it
  (success path; non-zero exit surfaces a `talkbox:` error and stops the
  container), using a fake-`podman`-on-`PATH` shim pattern.
- Add tests asserting the persistent executors' ordering: for onbox/netbox,
  `install_nft_deny_or_die` is invoked before the `setup.sh` `podman exec`.
  This may be expressed as a plan/ordering assertion where the executor is
  structured to emit an observable sequence, or via a fake-`podman` shim that
  logs the call sequence and the test asserts nft-precedes-setup. The exact
  mechanism is left to the implementing subagent.
- Add tests asserting `plan_volume_populate` and `container_sync_cmd`
  non-running path invoke `setup.sh` before their command (if those paths are
  changed to include setup).

### End-to-end tests — `test/e2e/onbox.bats`, `test/e2e/deny-allow.bats`,
`test/e2e/git-identity.bats`

- Update [`test/e2e/git-identity.bats`](../../../test/e2e/git-identity.bats)
  (L72 references `/run/talkbox/ready`) to assert setup completion via the
  actual side effects (git config written, dotfiles present) rather than the
  sentinel.
- Add (or extend) an onbox/netbox deny-allow e2e test asserting that a
  deny-listed outbound connection attempted **during setup** is blocked — e.g.
  plant a hook or `.bashrc` entry that attempts a denied connection, start the
  container, and verify the connection is dropped (the nft ruleset is in place
  before setup runs). This directly validates the ordering invariant.
  Gated behind `require_nft_and_internet`.
- The existing deny-allow e2e tests (passing path) continue to pass: the
  deny list is still enforced before the user command (now also before setup).
- A regression e2e asserting dotfiles are applied and git identity is
  configured in a freshly started onbox (covers that `setup.sh` runs and
  succeeds post-nft).

## Issue resolution

On completion, mark
[issue: agent-modified entrypoint runs before nft deny enforcement](../issues/agent-modified-entrypoint-pre-nft.gen.md)
complete in [`.llm/gen/issues/INDEX.gen.md`](../issues/INDEX.gen.md) (change
`- [ ]` to `- [x]`): the tampering vector is closed by Phase 14b, and the
pre-nft ordering of the trusted entrypoint body is closed by this phase
(setup now runs after `install_nft_deny_or_die`). Also mark the
[review](../reviews/entrypoint-before-nft-ordering.gen.md) as resolved if an
index of reviews is maintained.

## Related

- [Phase 14b: read-only bind-mount the entrypoint](phase-14b-entrypoint-readonly-bindmount.gen.md)
  — the preceding phase (Option F).
- [Review: entrypoint-before-nft ordering](../reviews/entrypoint-before-nft-ordering.gen.md)
  — Option B is the basis for this phase.
- [Phase 11a: entrypoint readiness synchronization](phase-11a-entrypoint-readiness-sync.gen.md)
  — the prior sentinel phase whose tests are rewritten here.
