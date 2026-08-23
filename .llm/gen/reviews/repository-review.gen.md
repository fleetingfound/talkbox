# Review: talkbox repository

Related spec: [SPEC.md](../../../SPEC.md)
Related map: [MAP.gen.md](../../../MAP.gen.md)
Related issues: [planner-executor-divergence](../issues/planner-executor-divergence.gen.md), [interactive-test-timeout-mismatch](../issues/interactive-test-timeout-mismatch.gen.md)

## Scope

A full review of the current implementation and test suite against [SPEC.md](../../../SPEC.md) on the dimensions of correctness, organization, conciseness, understandability and quality. Test runs and `make lint` were executed as part of the review.

## Test execution

| Suite | Command | Result |
|---|---|---|
| Unit | `make test-unit` | 139/139 pass |
| End-to-end | `make test-e2e` | 42/42 pass |
| Lint | `make lint` (shellcheck) | clean (exit 0) |

Both suites pass cleanly and the e2e suite exercises real `podman` containers via `systemd-run` per [SPEC.md §testing](../../../SPEC.md).

## Spec coverage

Phases 1–4 of the [plan index](../plans/INDEX.gen.md) are complete. Phase 5 (`merge`/`sync` subcommands and `custom_merge()`) is not yet implemented; this is a tracked, planned gap rather than a defect. Until Phase 5 lands, the `merge` and `sync` verbs are not recognized by [lib/options.sh](../../../lib/options.sh) and `custom_merge()` is absent from [lib/git.sh](../../../lib/git.sh), consistent with the plan's deferred scope. Everything else in SPEC.md — the three container kinds, mount/port resolution, root-filesystem and volume inheritance, lifecycle verbs, the gitdir-volume wiring, submodule absorption, the outside-gitdir refusal, and the bundle-based `fetch` — is implemented and covered by tests.

## What the implementation does well

- **Module split is clean and stable.** [lib/naming.sh](../../../lib/naming.sh), [lib/options.sh](../../../lib/options.sh), [lib/mounts.sh](../../../lib/mounts.sh), [lib/ports.sh](../../../lib/ports.sh), [lib/git.sh](../../../lib/git.sh), [lib/containers.sh](../../../lib/containers.sh) and [lib/common.sh](../../../lib/common.sh) each have a single responsibility, and [talkbox.sh](../../../talkbox.sh) stays a thin dispatcher. The naming module is fully pure and trivially testable.
- **Array-populating planners.** The Phase 1c refactor (recommended in [phase-1-onbox-scaffold.gen.md](phase-1-onbox-scaffold.gen.md)) landed: planners take a nameref out-array and append exact argument tokens, eliminating the fragile line-protocol re-parsing. Argument boundaries are preserved, so paths with spaces survive.
- **Planner/executor symmetry for onbox lifecycle.** `run_recontain` / `run_rebuild` / `run_rm_container` / `run_rm_image` call their `plan_*` counterpart and feed it to `execute_plan`. This is the shape the scaffold review asked for.
- **Mount handling is faithful to SPEC.** [lib/mounts.sh](../../../lib/mounts.sh) correctly expands `~`/`$HOME`/`$PROJECT`, derives default dests, collapses identical dests (last source wins) and depth-orders nested dests shallow-to-deep so deeper mounts override shallower ones. [SPEC.md §mount precedence](../../../SPEC.md) is satisfied. Read mounts are `:ro`; write mounts are not. Netbox/offbox write mounts become named volumes `<slug>.<container>.write.<dest-slug>` via `mount_volume_args`.
- **Network options match the spec exactly.** `plan_onbox`/`plan_netbox` emit `pasta[:<ports>]`; `plan_offbox` emits `pasta[:<ports>],-i,lo,-I,talkbox0` (with and without ports). `--cap-drop=NET_ADMIN`/`NET_RAW` are always present.
- **Inheritance planner is well-tested.** `inherit_source` correctly implements the default chain (netbox←onbox, offbox←netbox←onbox←base), `--fresh` (forces base) and `--inherit` (explicit, with fallback to base when the named source is absent). The `--fresh`-overrides-`--inherit` precedence is correct.
- **Temporary containers are networkless with read-only host sources.** `plan_volume_populate` and `gitdir_bundle_cmd` both use `--network=none`; population containers bind the host source `:ro`. This satisfies [SPEC.md §implementation](../../../SPEC.md) ("temporary containers … should be created without any network access … host source must be mounted read-only").
- **Gitdir-volume wiring is correct and well-pinned.** The gitdir volume is a fresh git repo wired to `/host/git/` as the `host` remote, not a copy of the host git dir; the e2e test in [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats) verifies the config and the absence of host user config leakage. The `fetch` action transports history via `git bundle create --all` and `git fetch … +refs/heads/*:refs/remotes/<container>/*`, which avoids transferring configs/hooks as required.
- **Test harness is solid.** [test/run-suite.sh](../../../test/run-suite.sh) wraps the suite in `systemd-run` (with a `timeout(1)` fallback), sets `BATS_TEST_TIMEOUT` for per-test limits, parses TAP and writes a YAML run record. [test/e2e/helpers.bash](../../../test/e2e/helpers.bash)'s `sdrun` correctly wraps each podman-invoking call. Hermeticity is good: `mk_talkbox` neutralizes the default mounts/ports so e2e is self-contained.
- **ShellCheck is clean** across all scripts in the `SHELL_SCRIPTS` set, and `shfmt` formatting is applied.

## Significant shortcomings

### 1. Planner/executor divergence — netbox/offbox plan functions are unused and incomplete (issue)

This is the most consequential finding; see [issue: planner/executor divergence](../issues/planner-executor-divergence.gen.md). Summary:

- Seven `plan_*` functions ([lib/containers.sh](../../../lib/containers.sh) lines 57, 375, 396, 417, 440, 463, 487) are never called from production code — only from unit tests.
- The production executors `run_onbox`/`run_netbox`/`run_offbox` inline their create/start/exec sequence instead of calling `plan_*_run`.
- `run_netbox_recontain`/`run_offbox_recontain`/`run_netbox_rebuild`/`run_offbox_rebuild` assemble their own plan arrays instead of calling the corresponding `plan_*` functions.
- Those four netbox/offbox `plan_*_recontain`/`plan_*_rebuild` functions are also *incomplete*: they omit the `plan_netbox_populate`/`plan_offbox_populate` step that the executors perform, so the unit tests in [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) pin a `commit→rm→create→start` sequence that does not match the executor's `commit→rm→run(populate)→create→start` sequence.

The net effect is that a meaningful slice of the unit suite gives false confidence: it tests dead code, and it codifies an incomplete plan. The onbox lifecycle path is the model to follow (`run_recontain` → `plan_recontain` + `execute_plan`).

### 2. `create_netbox`/`create_offbox` read global `ONBOX_FRESH`/`ONBOX_INHERIT` directly

[lib/containers.sh](../../../lib/containers.sh) `create_netbox`, `create_offbox`, and the four `run_*_recontain`/`run_*_rebuild` executors all read `ONBOX_FRESH` and `ONBOX_INHERIT` as globals set by `parse_onbox_options` in [lib/options.sh](../../../lib/options.sh). Every other input to these functions (project, interactive, mounts, ports, image) is passed positionally. The two inheritance parameters are the exception, coupled to parser-set globals rather than threaded through as arguments.

This is inconsistent and slightly brittle: a caller that sourced `lib/containers.sh` and invoked `create_netbox` directly (e.g. a future test or a refactor) would silently get default inheritance unless it also set the globals. Threading `fresh` and `inherit` as positional arguments (or folding them into a single options record passed by nameref) would match the rest of the signature discipline.

### 3. `--inherit onbox` for offbox silently falls back to host sources for volumes

`plan_offbox_populate` keys the "copy from netbox volume" branch on `root_source == netbox` ([lib/containers.sh](../../../lib/containers.sh) line 568, 578). When the user runs `offbox --inherit onbox`, `inherit_source` returns `onbox`; `plan_offbox_populate` then takes the `else` branch and copies the worktree and write volumes from the host. This is a reasonable fallback (onbox has no volumes to copy from), but [SPEC.md §inheritance options](../../../SPEC.md) states `--inherit <source>` makes the container "inherit its root filesystem and read-write volumes from" the source. The spec does not address the case where the chosen source has no volumes, so the implementation's host-fallback is defensible, but it is an under-documented deviation. Either the spec should acknowledge the fallback, or `plan_offbox_populate` should treat `root_source == onbox` the same as `base` explicitly.

### 4. `parse_onbox_options` does not recognize `merge`/`sync` (Phase 5 gap, but the parser is not structured to add them cleanly)

[lib/options.sh](../../../lib/options.sh) handles `fetch` as a special non-flag token (verb) only when `after_command` is false, and recognizes `--all` globally. Adding `merge` and `sync` verbs in Phase 5 will require adding two more `case` branches that set `ONBOX_VERB` plus a branch-name argument (`ONBOX_BRANCH` or similar). The current parser has no notion of a verb-with-argument, so the addition will be another ad-hoc branch rather than a general "subcommand with positional args" mechanism. Not a bug today, but the parser's shape will need a small generalization for Phase 5; worth flagging now so it isn't surprise scope creep.

### 5. `dest_slug('/')` produces an empty slug

[lib/naming.sh](../../../lib/naming.sh) `dest_slug` returns the empty string for the dest `/`, which would yield a malformed volume name like `<slug>.netbox.write.` (trailing dot). Mounting a write volume at `/` is nonsensical, so this is unlikely to be hit in practice, but there is no guard. A one-line `[ -z "$dest" ] && die` (or returning a sentinel) would make the failure mode explicit.

### 6. The interactive-timeout issue doc is stale

[issue: interactive e2e test has inconsistent timeouts](../issues/interactive-test-timeout-mismatch.gen.md) describes `set timeout 90` in the `expect` script against `SD_TIMEOUT=60`. The code has since been changed: the `expect` scripts in [test/e2e/onbox.bats](../../../test/e2e/onbox.bats) and [test/e2e/lifecycle.bats](../../../test/e2e/lifecycle.bats) now use `set timeout 30`, and `SD_TIMEOUT` defaults to `INDIVIDUAL_TEST_TIMEOUT - 5` = 55s, so expect's 30s timeout can now fire before systemd's 55s kill. The issue appears resolved in code, but it remains unchecked (`[ ]`) in [issues/INDEX.gen.md](../issues/INDEX.gen.md) and the issue body still describes the old mismatch. Either mark it `[x]` and note the resolution, or update the body to reflect the current 30s/55s relationship.

## Style and minor observations

- **Shebangs on sourced libs.** `lib/*.sh` files begin with `# shellcheck shell=bash` (good) but no `#!/usr/bin/env bash` shebang — this is correct for sourced libraries and consistent across the set. (The earlier scaffold review's "shebang in sourced libs" note no longer applies.)
- **`entrypoint.sh` uses `exec bash -c "$*"`.** Fine under the single-command-string contract in [SPEC.md §command execution](../../../SPEC.md). `$*` joins argv with the first `IFS` char (space); for the `sleep infinity` main process this produces the expected `bash -c "sleep infinity"`. `exec "$@"` would be more robust if the entrypoint ever received an argv array, but the current contract doesn't require it.
- **`image/Containerfile` installs `sudo` with NOPASSWD for `dev`.** SPEC.md doesn't mention `sudo`. It's a harmless convenience but slightly broadens the container's privilege surface; worth a note in the spec or a comment if intentional.
- **`run_onbox`/`run_netbox`/`run_offbox` always `podman stop -t 1` at session end.** This keeps the detached container's `conmon` from pinning the `systemd-run` cgroup, which is the right call for the test harness. The 1-second stop timeout is aggressive for a user mid-work, but acceptable since the container persists and is simply restarted next session.
- **`lib/git.sh::execute_fetch_plan` splits on `git fetch`.** The plan is `[podman, run, …, git, bundle, create, …, git, fetch, …]`; the executor flushes the accumulated `podman run` when it sees `git` followed by `fetch`, then accumulates and runs the `git fetch` at the end. This is a clever but implicit protocol — a comment (or a `\0`-delimited command separator in the plan) would make the boundary obvious. Currently works correctly.
- **Duplicate `array_contains`/`array_has_none`/`plan_subcommands` helpers.** These are copy-pasted across [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) and [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats). Extracting them into [test/unit/helpers.bash](../../../test/unit/helpers.bash) (which currently only has `load_lib`) would reduce duplication. Minor.
- **`talkbox.sh` `sandbox_action` computes `write_mounts` via `mount_volume_args` but onbox's `onbox_action` uses `mount_args` for writes.** This is correct (onbox bind-mounts writes; netbox/offbox use volumes) but the two action functions diverge in which helpers they call, which is a minor readability cost. A shared helper that produces both the bind-mount list and the volume list would centralize the mode logic.

## Test quality

- **Unit/e2e split is healthy.** Pure logic (naming, options, mount/port parsing, planner output, inheritance) is fast and hermetic at unit level; podman-invoking behaviour is covered by e2e under `systemd-run`.
- **Coverage of SPEC behaviours is broad.** Workdir, host-writable worktree (onbox), volume isolation (netbox/offbox), internet on/off, dotfile copy and override, read-only bind-mount enforcement, `--read`/`--write`/`--port`, all four lifecycle verbs, root-filesystem inheritance, `--fresh`/`--inherit`, git remote wiring, submodule blocking, outside-gitdir refusal, and bundle-based `fetch` (including `--all`) are all exercised end-to-end.
- **The gap is the planner/executor divergence** (shortcoming 1): the unit tests for `plan_*_run` and the netbox/offbox `plan_*_recontain`/`plan_*_rebuild` assert behaviour of functions the production path doesn't use, and assert an incomplete plan for the latter four. Resolving this would meaningfully raise the value of the unit suite.
- **Interactive tests use `expect` with a 30s timeout** and exercise both the default shell and `-c --interactive`. Good coverage of the tty path that noninteractive tests can't reach.
- **Hermeticity is strong.** `mk_talkbox` neutralizes default mounts/ports; `mk_project` makes a fresh git repo per test; teardowns remove containers, images and volumes. The internet-dependent tests skip cleanly when the host is offline.

## Recommendations (ordered by impact)

1. **Resolve the planner/executor divergence.** Either wire the executors to their `plan_*` counterparts and complete the netbox/offbox recontain/rebuild plans with the missing `plan_*_populate` step (updating the lifecycle tests accordingly), or delete the seven unused `plan_*` functions and their tests. The first option restores symmetry and makes the unit suite meaningful. See [issue](../issues/planner-executor-divergence.gen.md).
2. **Thread `fresh`/`inherit` as arguments** to `create_netbox`/`create_offbox`/`run_*_recontain`/`run_*_rebuild` instead of reading `ONBOX_FRESH`/`ONBOX_INHERIT` globals, for signature consistency.
3. **Reconcile or document `--inherit onbox` for offbox volumes** (host-fallback behaviour vs. the spec's literal wording).
4. **Update or close the stale interactive-timeout issue** to reflect the current 30s/55s timeout relationship.
5. **Guard `dest_slug` against the empty result** for the `/` dest.
6. **Extract the duplicated unit test helpers** (`array_contains`/`array_has_none`/`plan_subcommands`) into `test/unit/helpers.bash`.

None of these block current correctness — the implementation passes all 181 tests and meets the implemented spec slice. They are improvements to test fidelity, consistency and clarity ahead of Phase 5.
