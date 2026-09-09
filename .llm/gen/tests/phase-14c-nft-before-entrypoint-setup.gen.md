# Phase 14c: Install nft ruleset before entrypoint setup runs

Test document for [Phase 14c: Install nft ruleset before entrypoint setup runs](.llm/gen/plans/phase-14c-nft-before-entrypoint-setup.gen.md), which refactors the persistent-container startup sequence so the setup body (`image/setup.sh`, extracted from the deleted `image/entrypoint.sh`) runs via `podman exec` **after** `install_nft_deny_or_die` instead of running as the image `ENTRYPOINT` at `podman start`, removing the tmpfs `/run/talkbox` sentinel and `wait_for_entrypoint` poll, and updating the one-shot paths (`container_sync_cmd` non-running path) to invoke `setup.sh` explicitly.

The implementation was simulated in a scratch copy (`/tmp/opencode/tb-sim`) to validate that every test here passes once the plan is implemented: `make test-unit` 251/251 and `make test-e2e` 76/76 both pass against the simulation, while the current repository shows exactly the intended red state (unit 235 pass / 16 fail, e2e 72 pass / 4 fail).

## New tests

### `test/unit/containers.bats` (2)

Executor-ordering tests using a fake-`podman`-on-`PATH` shim that logs every invocation (draining stdin so the nft ruleset pipeline cannot SIGPIPE) and answers `podman inspect -f '{{.State.Pid}}'` with a fake PID, per the plan's "fake-`podman` shim that logs the call sequence" suggestion (plan L243-248):

- `run_onbox applies the nft deny rules before running setup.sh and runs setup.sh before the user command` — with a non-empty deny array, asserts `start` < `unshare … nsenter … nft` < `exec <ctr> setup.sh` < `exec <ctr> bash -c echo hi` in the logged call sequence. **Observed red:** no `setup.sh` exec exists today (the setup body runs inside the image `ENTRYPOINT` at `podman start`), so the `setup.sh` log line is missing.
- `run_onbox stops the container and raises a talkbox error when the setup.sh exec fails` — shim fails the `setup.sh` exec; asserts non-zero status, a `talkbox:` message and a `podman stop` in the log (mirroring the `install_nft_deny_or_die` pattern; plan L149-154 "The `setup.sh` exec must succeed (non-zero exit stops the container and raises a `talkbox:` error…)"). **Observed red:** today there is no `setup.sh` exec at all, so the run succeeds and the container is never stopped.

### `test/unit/netbox-offbox.bats` (4)

Same shim pattern, covering the other executors per the plan's reordering requirements (plan L149-163):

- `run_netbox applies the nft deny rules before running setup.sh and runs setup.sh before the user command` — same `start` < `nft` < `setup.sh` < user-command assertions as `run_onbox`. **Observed red** (no `setup.sh` exec).
- `run_offbox runs setup.sh after start and before the user command, with no nft step` — asserts `start` < `setup.sh` < user command and that no `nsenter` line is logged (offbox omits the nft step). **Observed red.**
- `run_netbox recontain and rebuild run setup.sh after the nft deny install and before stopping the container` — for both verbs asserts `nft` < `setup.sh` < `stop`, per plan L155-161 ("setup exec is inserted between nft and the final `podman stop`… they should still run `setup.sh` so the committed/inherited state is initialised"). **Observed red.**
- `run_offbox recontain and rebuild run setup.sh after start and before stopping the container, with no nft step` — asserts `start` < `setup.sh` < `stop` with no `nsenter` line for both verbs (plan L162-163). **Observed red.**

### `test/e2e/deny-allow.bats` (1)

- `onbox --deny-ip blocks a deny-listed connection attempted during setup` — gated behind `require_nft_and_internet` (plan L262-265). The gitdir volume is pre-planted with a `config` containing `remote.host.uploadpack`, so the gitdir-init `git fetch host` (the first setup step that runs code) executes a host-supplied upload-pack script which attempts `curl http://1.1.1.1/` and records `REACHED`/`BLOCKED` in the worktree. The test asserts `BLOCKED`. **Observed red:** today the entrypoint runs the fetch before `install_nft_deny_or_die`, so the connection succeeds and `REACHED` is recorded — the assertion `[[ "$output" == *'BLOCKED'* ]]` fails at deny-allow.bats L192.

### `test/e2e/onbox.bats` and `test/e2e/netbox-offbox.bats` (2, replacing the removed entrypoint-tampering tests)

- `onbox container provides the setup.sh script` — `head -n 1 /usr/local/bin/setup.sh` returns the trusted shebang, pinning the new `COPY --chmod=755 setup.sh /usr/local/bin/setup.sh` in the Containerfile (plan L115-123, L134-140). **Observed red:** the current image installs only `entrypoint.sh`.
- `netbox --recontain recreates the container with setup.sh available` — after `netbox --recontain` (which must re-run setup so the recreated container is initialised, plan L155-161), `head -n 1 /usr/local/bin/setup.sh` returns the trusted shebang. **Observed red:** the committed root image carries no `setup.sh`.

## Tests edited

### tmpfs-mount tests rewritten into absence assertions (9)

Per the plan, the tmpfs sentinel is obsolete and the `--tmpfs /run/talkbox` planner entries are removed (plan L142-146 "remove the `--tmpfs /run/talkbox` entries (the sentinel is obsolete)", L219 "The `--tmpfs /run/talkbox` planner entries — removed (obsolete)", L233-237 "Replace with assertions that the three persistent planners **do not** emit a `--tmpfs /run/talkbox` entry"):

- `test/unit/containers.bats`: `onbox plan mounts a tmpfs at /run/talkbox for the entrypoint readiness sentinel` → `onbox plan does not mount a tmpfs at /run/talkbox`; `onbox recontain plan propagates the /run/talkbox tmpfs to podman create` → `onbox recontain plan does not emit a /run/talkbox tmpfs`; `onbox rebuild plan propagates the /run/talkbox tmpfs to podman create` → `onbox rebuild plan does not emit a /run/talkbox tmpfs`. All assert `array_has_none '--tmpfs'` and `array_has_none '/run/talkbox'` over the plan array. **Observed red** (planners still emit the tmpfs).
- `test/unit/netbox-offbox.bats`: `netbox plan mounts a tmpfs …` and `offbox plan mounts a tmpfs …` → do-not-mount versions; `netbox recontain plan propagates the /run/talkbox tmpfs …`, `offbox recontain …`, `netbox rebuild …`, `offbox rebuild …` → do-not-emit versions. **Observed red.**

### `test/e2e/git-identity.bats` (1)

`a git command in a freshly started container runs only after the entrypoint readiness sentinel appears` (which grepped the shim log for `/run/talkbox/ready`, L72) is rewritten as `a git command in a freshly started container runs only after setup.sh has run`: the same shim pattern now asserts a logged `exec <ctr> setup.sh` line precedes the user-command line, and the command asserts the setup side effects (git identity configured, `GIT-SUCCEEDED`), per plan L256-258 ("assert setup completion via the actual side effects (git config written, dotfiles present) rather than the sentinel"). **Observed red:** no `setup.sh` exec is logged today.

### `test/unit/git-transport.bats` (1)

`container_sync_cmd assembles a no-network temporary podman run for a stopped container` — the plan changes the non-running one-shot command so `setup.sh` runs before the sync script (plan L172-175 "update the one-shot command so `setup.sh` runs before the sync script… The command becomes `bash -c "setup.sh && exec bash -c '$script' _ <branches>"` or equivalent"), so the exact-shape assertions (`--entrypoint=/bin/bash`, `-c $script _`) were replaced by invariant assertions: the joined command contains `setup.sh` earlier than the sync-script text, and the branches (`master feature`) are still passed. Mount/network/image assertions are unchanged. **Observed red:** the current command contains no `setup.sh`.

## Tests removed

### Entrypoint bind-mount tests (9)

`image/entrypoint.sh` is **deleted** by this phase, so the planners cannot keep mounting it and these tests cannot pass after implementation — plan L127-132: "`image/entrypoint.sh` — **deleted**. Its setup body moves to `image/setup.sh`; the `exec` tail and the sentinel-write block (`/run/talkbox/ready`) are removed with it. The image no longer references `entrypoint.sh` (no `COPY`, no `ENTRYPOINT`)…" and SPEC.md L198 (the prior "`entrypoint.sh` is on `PATH`" sentence removed):

- `test/unit/containers.bats`: `onbox plan bind-mounts the host entrypoint read-only`; `onbox recontain plan propagates the entrypoint read-only bind mount to podman create`; `onbox rebuild plan propagates the entrypoint read-only bind mount to podman create`.
- `test/unit/netbox-offbox.bats`: `netbox plan bind-mounts the host entrypoint read-only`; `offbox plan bind-mounts the host entrypoint read-only`; `netbox recontain plan propagates the entrypoint read-only bind mount…`; `offbox recontain …`; `netbox rebuild …`; `offbox rebuild …`.

### `wait_for_entrypoint` tests (2)

The function is removed and its sentinel poll is obsolete — plan L147-148 "`wait_for_entrypoint` (L188-193): remove (no longer called). The `podman exec`-based sentinel poll is obsolete", L218 "`wait_for_entrypoint` — removed (obsolete)"; the new synchronous ordering is covered by the executor tests above:

- `test/unit/containers.bats`: `wait_for_entrypoint returns success once podman exec reports the sentinel file`; `wait_for_entrypoint dies with a talkbox error when the sentinel never appears`.

### Entrypoint-tampering e2e tests (2)

Their subject (`/usr/local/bin/entrypoint.sh`) is deleted by the plan (L127-132), so they cannot pass after implementation; each is replaced by the corresponding `setup.sh`-presence test listed under New tests:

- `test/e2e/onbox.bats`: `onbox entrypoint is a read-only bind mount that resists tampering`.
- `test/e2e/netbox-offbox.bats`: `netbox --recontain re-applies the trusted entrypoint after a tampering attempt`.

## Coverage notes

- The existing e2e regression coverage for "dotfiles applied and git identity configured in a freshly started onbox" (plan L268-270) is already provided by the retained `global dotfiles are copied into /home/dev`, `project dotfiles override global dotfiles in /home/dev` and the git-identity e2e tests, which continue to pass.
- `plan_volume_populate` is left untested for `setup.sh`: the plan leaves its update conditional (L168-171 "the implementing agent should confirm whether `plan_volume_populate` actually needs setup at all … if not, leave it unchanged and only update `container_sync_cmd`"), so no assertion is made either way.
- The plan's `wait_for_entrypoint`-style helper unit tests (L239-242) are conditional on a helper being introduced; the `run_onbox`/`run_netbox` failure test covers the behaviour regardless of shape.
