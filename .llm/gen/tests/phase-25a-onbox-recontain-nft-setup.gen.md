# Tests: Phase 25a onbox `--recontain`/`--rebuild` install the nft deny rules and run `setup.sh`

Red/green test pass for [Phase 25a: onbox `--recontain`/`--rebuild` install the nft deny rules and run `setup.sh`](../plans/phase-25a-onbox-recontain-nft-setup.gen.md), which aligns the `run_recreate` start-time tail in `lib/containers.sh` with `run_container` — nft deny install for every container except `offbox`, then the `setup.sh` exec for all containers, then stop — so that `onbox --recontain`/`--rebuild` become behaviourally identical to `netbox`'s, resolving [onbox `--recontain` skips nft deny rule installation and `setup.sh`](../issues/onbox-recontain-skips-nft-and-setup.gen.md).

No files are created by the plan and no test file is added; the pass supersedes five tests that pinned the skip and extends one e2e test to observe the new behaviour. No test was removed.

## Tests edited

All five edited tests pin the new container-uniform ordering (`start` < nft install < `setup.sh` exec < `stop`) required by `SPEC.md`:

> "For the `onbox` and `netbox` containers, the restrictions are enforced via `nft` before `image/setup.sh` is invoked." (`SPEC.md`, network section)

> "After the container has been started, then `image/setup.sh` is invoked with `podman exec` in order to install the dotfiles." (`SPEC.md`, dotfiles section)

The current implementation violates both for `onbox` recontain/rebuild: `run_recreate` guards the nft install and the setup exec with nested `!= onbox` / `!= offbox` conditions, so `onbox --recontain` runs neither (the exact skip pinned by the four unit tests below, per the plan's "the tests pinning the skip are superseded and rewritten to pin the new ordering").

### `test/unit/lifecycle.bats`

- `run_recreate onbox no removes, recreates and starts the onbox container, installing nft, running setup and stopping` (was "…, running no nft, setup or user command"): the three zero-count assertions `podman_count 'unshare' -eq 0`, `podman_count 'nsenter' -eq 0` and `podman_count '^exec ' -eq 0` are removed and replaced by presence-and-ordering assertions for the nft pipeline (`unshare.*nsenter.*nft`) and the `setup.sh` exec (`^exec talkbox-proj.onbox setup.sh$`), chained `start` < nft < setup < stop alongside the unchanged rm → volume-rm → create → start ordering. The non-empty deny array (`DENY=(1.1.1.1)`) was already passed, so the nft invocation is expected once the skip is removed. **Observed red:** fails at the presence assertion — no `unshare`/`nsenter`/`exec` lines are logged by the current `run_recreate` for `onbox`.
- `run_recreate onbox yes builds the base image first, then installs nft and runs setup before stopping` (was "…builds the base image first, then recreates and starts the onbox container"): same replacement of the `unshare` and `^exec` zero-count assertions by the nft/setup presence-and-ordering chain appended to the unchanged build → rm → create → start ordering; the `image exists` zero-count and the build-line token assertions are retained. **Observed red:** fails at the presence assertion for the same reason.

### `test/unit/netbox-offbox.bats`

- `run_recreate recontain and rebuild order start, the nft install, setup.sh and stop per container for onbox, netbox and offbox` (was "…for netbox and offbox"): the data-driven loop is extended with `onbox` as a third container, using the netbox-shaped columns (nft-before-setup: `pre_patterns[0]='unshare.*nsenter.*nft'`, empty absent pattern) so the loop now pins the identical recontain/rebuild start-time tail for all three containers. **Observed red:** fails at the `pre_line` presence assertion for the `onbox` iterations (no nft install is logged). Note: the array literal must be space-separated (`('' '' 'nsenter')`); a stray comma after an empty-string element (`('', '' …)`) glues the comma onto the element in bash and silently turns the empty "no check" sentinel into a `,` pattern.

### `test/unit/dispatcher.bats`

- `talkbox.sh onbox --recontain recreates without populating and installs nft and runs setup` (was "…recreates without populating, nft or setup"): the `^unshare` and `^exec` zero-count assertions are replaced by presence-and-ordering assertions — `^unshare nsenter` after `start`, then `^exec talkbox-proj.onbox setup.sh$` after the nft line and before `stop -t 5` — while the no-populate (`^run` count 0), no-commit (`^commit` count 0), no-build (`^build` count 0) and rm → volume-create → create ordering assertions are retained. The dispatcher reads the repo's non-empty `defaults/deny.ip`, so the nft invocation is expected. **Observed red:** fails at the `^unshare nsenter` presence assertion.
- `talkbox.sh onbox --rebuild builds the base image before recreating`: the `^unshare` and `^exec` zero-count assertions are replaced by the same presence-and-ordering assertions appended after `start`, retaining the build-line presence, build → rm → create ordering and no-commit assertions. **Observed red:** fails at the `^unshare nsenter` presence assertion.

### `test/e2e/lifecycle.bats`

- `onbox --recontain recreates the container and starts it`: the test additionally observes that `setup.sh` ran in the recreated container, by wrapping the `onbox --recontain` invocation in the `mk_podman_logging_shim`/`e2e_use_podman_shim` logging delegate (the pattern of `test/e2e/git-identity.bats` "a git command in a freshly started container runs only after setup.sh has run") and asserting that the log records `exec $CTR setup.sh` between `start $CTR` and `stop -t 5 $CTR`. The pre-existing assertions (identity override + container commit before recontain, `FRESH` worktree probe after) are unchanged. The plan's alternative observation ("the host git identity propagated by `setup.sh` is present when the container is next used") cannot discriminate here because the next `onbox -c` use runs `setup.sh` itself via `run_container`, so the podman-log observation is used instead. The e2e deny set is empty (`mk_talkbox` empties the copied `defaults/deny.ip`), so no nft invocation is expected and hosts without `nft` are unaffected, per the plan's behavioural note. **Observed red:** fails at the presence assertion — the recontain log contains no `exec … setup.sh` line.

## Tests removed

None. Every pre-existing test is either untouched (all create-path, `netbox`/`offbox` and harness tests) or superseded by an edit listed above; no test that would pass after the plan is implemented was deleted.

## Verification

- **Red (observed on the current implementation):** `make test-unit` → 315 total, 5 failures — exactly the edited unit tests (`talkbox.sh onbox --recontain…`, `talkbox.sh onbox --rebuild…`, both `run_recreate onbox …` tests, the extended per-container ordering loop test), each failing at a presence assertion for the missing nft/setup invocations; `make test-e2e` → 78 total, 1 failure — the extended e2e recontain test. No other test regressed.
- **Green (validated):** the plan's single production change applied to a scratch copy of the tree (`run_recreate`'s nested `!= onbox`/`!= offbox` guards replaced by the `run_container`-shaped tail: nft install unless `offbox`, then the setup exec, then stop; repo core files untouched) yields `make test-unit` → 315/315 and `make test-e2e` → 78/78, and `make lint`/`make format` pass with the edited tests, confirming the tests fail for the planned functionality and pass once it is implemented.
