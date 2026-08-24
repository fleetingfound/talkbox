# Review: repository-wide correctness, organization and quality

## scope

This review surveys the whole talkbox repository — the dispatcher ([talkbox.sh](../../../talkbox.sh)), the [lib/](../../../lib) modules, the [image/](../../../image) container definition, the [defaults/](../../../defaults) configuration, and the [test/](../../../test) harness — against the specification in [SPEC.md](../../../SPEC.md). It complements the earlier [git-transport review](git-transport-review.gen.md), which covers the merge/sync layer in depth; that material is not repeated here.

## summary

The repository is well-organised, the implementation is faithful to the specification, and the test suite is comprehensive (162 unit tests, 57 e2e tests, plus canary/timeout harnesses — all green on a clean run, ShellCheck clean). Code is split into small, single-responsibility modules under `lib/`, each with a focused unit-test file mirroring its shape. The plan/execute pattern for podman commands is consistently applied to lifecycle verbs. The e2e suite drives real containers through `systemd-run` with timeout enforcement, matching the spec's safety requirements.

A handful of issues were identified during this review and are filed separately:

- [README.md refers to `openbox` instead of `onbox`](../issues/readme-openbox-onbox-mismatch.gen.md) — documentation bug.
- [E2e `--port` test has a TOCTOU race in `free_host_port`](../issues/e2e-port-test-toctou-race.gen.md) — test flakiness.
- [`.bashrc` references undefined colour variables](../issues/bashrc-undefined-colour-variables.gen.md) — cosmetic.

Several additional observations (not filed as issues because they are stylistic or theoretical) are noted at the end.

## organization

### module structure

[lib/](../../../lib) is decomposed into small, single-responsibility files:

| file | responsibility |
|------|----------------|
| [common.sh](../../../lib/common.sh) | `die()` / `trim()` helpers |
| [naming.sh](../../../lib/naming.sh) | pure name/slug derivation |
| [options.sh](../../../lib/options.sh) | argument parsing |
| [mounts.sh](../../../lib/mounts.sh) | mount-spec parsing, expansion, depth-ordering |
| [ports.sh](../../../lib/ports.sh) | port parsing/dedup |
| [merge.sh](../../../lib/merge.sh) | location-agnostic `custom_merge` |
| [git.sh](../../../lib/git.sh) | host-side git helpers, fetch/merge/sync actions |
| [containers.sh](../../../lib/containers.sh) | podman planning, execution, lifecycle |

Each `lib/*.sh` re-derives `TALKBOX_ROOT` from `BASH_SOURCE` (with `TALKBOX_ROOT` already exported by `talkbox.sh` taking precedence), so they can be sourced independently for unit testing. Naming-convention helpers ([naming.sh](../../../lib/naming.sh)) are pure functions, which makes them trivial to test and reason about.

### plan/execute pattern

The lifecycle verbs (`recontain`, `rebuild`, `rm-container`, `rm-image`) consistently follow a planner + executor pattern:

- A `plan_*` function builds a flat array of podman subcommand tokens.
- `execute_plan` (or `execute_fetch_plan` for the git-bundle path) walks the array, splitting on `podman` boundaries to invoke each subcommand in turn.

This is clean and works because each `podman` invocation is self-contained. The onbox lifecycle path (`run_recontain` / `run_rebuild`) and the netbox/offbox lifecycle paths (`run_netbox_recontain` / `run_offbox_recontain` / `run_netbox_rebuild` / `run_offbox_rebuild`) all flow through their corresponding `plan_*` functions and `execute_plan`. This resolves the previously-filed [planner/executor divergence](../issues/planner-executor-divergence.gen.md) for the lifecycle path.

### normal-run path

The normal-run path (`run_onbox` / `run_netbox` / `run_offbox`) does **not** use a `plan_*_run` function — it inlines the `podman create` / `podman start` / `podman exec` / `podman stop` sequence directly. This is a reasonable stylistic choice (the run path has conditional logic — "container exists?" — that does not fit a static plan), but it means the unit tests for `plan_onbox` / `plan_netbox` / `plan_offbox` (the create-args builders) are pinning only the `podman create` arguments, not the create→start→exec→stop sequence. The full sequence is covered by e2e tests.

## correctness

### mount handling

[mounts.sh](../../../lib/mounts.sh) correctly implements the spec's mount semantics:

- Source/dest splitting on `:` with optional whitespace ([SPEC.md](../../../SPEC.md) §"mount specification format").
- `~` / `$HOME` expansion in source and dest; `$PROJECT` expansion in dest only.
- Default dest derivation (`/host/read/<basename>` / `/host/write/<basename>`).
- Blank/comment-line skipping.
- File-then-CLI union, with CLI overriding file for identical dests (last-wins dedup iterating end-to-start).
- Stable depth-ordered sort (shallower first) so deeper mounts override shallower permissions.

`mount_volume_args` correctly emits write mounts as named volumes (`<slug>.<container>.write.<dest-slug>`) for netbox/offbox, matching [SPEC.md](../../../SPEC.md) §"read-write mounts".

### networking

[containers.sh](../../../lib/containers.sh) `plan_onbox` / `plan_netbox` / `plan_offbox` produce the correct `pasta` network strings:

- onbox / netbox: `pasta` (no ports) or `pasta:-T,<p1>,-T,<p2>` (with ports).
- offbox: `pasta:-i,lo,-I,talkbox0` (no ports) or `pasta:-T,<p1>,-T,<p2>,-i,lo,-I,talkbox0` (with ports).

`--cap-drop=NET_ADMIN --cap-drop=NET_RAW` is applied uniformly. The offbox loopback-only restriction is verified by the e2e test "offbox blocks internet access".

### inheritance

`inherit_source` correctly implements [SPEC.md](../../../SPEC.md) §"filesystem inheritance":

- `--fresh` always yields `base`.
- `--inherit <source>` yields the source if it exists, else `base`.
- Default: netbox inherits from onbox (if exists) else base; offbox inherits from netbox (if exists), then onbox (if exists), else base.

`plan_offbox_populate` conditionally copies the worktree and write volumes from netbox when `root_source == netbox` and the netbox volume exists, otherwise from the host. This is a defensible reading of the spec's "by default" language for read-write volume inheritance, though the spec is slightly ambiguous about whether `--inherit onbox` should suppress the netbox-volume copy.

### git transport

Covered in detail in [the git-transport review](git-transport-review.gen.md). The `custom_merge` logic, bundle-based fetch, and sync-via-temporary-or-running-container paths are all spec-compliant. One minor spec-interpretation note: `custom_merge_current` Case 1 uses `git diff --cached --quiet && git diff --quiet`, which treats untracked files as "dirty" (stricter than a literal reading of "clean relative to HEAD"). This is safe and conservative.

### user mapping

All containers and temporary helper containers use `--userns=keep-id:uid=1000,gid=1000`, matching [SPEC.md](../../../SPEC.md) §"user mapping". The `dev` user (uid 1000) is created in [image/Containerfile](../../../image/Containerfile) with passwordless sudo, which is appropriate for a development container.

### temporary-container safety

[SPEC.md](../../../SPEC.md) §"implementation" requires that temporary helper containers have no network access and mount host sources read-only. `plan_volume_populate` and `gitdir_bundle_cmd` both use `--network=none` and mount host sources with `:ro`. Verified.

## tests

### unit suite (162 tests, all passing)

Each `lib/*.sh` has a matching `test/unit/*.bats`:

- [naming.bats](../../../test/unit/naming.bats) — 18 tests covering all slug/name derivations, including edge cases (trailing slashes, non-alphanumeric runs, already-slugged input).
- [options.bats](../../../test/unit/options.bats) — 27 tests covering every option/verb/positional combination, including the `-c fetch` vs `fetch` disambiguation.
- [mounts.bats](../../../test/unit/mounts.bats) — 16 tests covering parsing, expansion, dedup, depth-ordering, and volume-mount emission.
- [ports.bats](../../../test/unit/ports.bats) — 7 tests covering file parsing, dedup, and union.
- [merge.bats](../../../test/unit/merge.bats) — 11 tests covering all `custom_merge` cases (current-branch Cases 1-3, other-branch, non-descendant, absent remote).
- [git.bats](../../../test/unit/git.bats) — 13 tests covering git-dir resolution, classification, submodule enumeration, `current_branch` on detached HEAD, and `plan_fetch` output.
- [git-transport.bats](../../../test/unit/git-transport.bats) — 6 tests covering `resolve_branches`, `sync_script`, `container_sync_cmd` (running + stopped paths), `execute_fetch_plan` boundary splitting, and `run_sync_in_container` delegation.
- [containers.bats](../../../test/unit/containers.bats) — 16 tests covering `plan_onbox` output (workdir, userns, network, caps, mounts, dotfiles, git mounts, name, image, interactive flags).
- [netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) — 14 tests covering `inherit_source` (all combinations), `plan_volume_populate`, `plan_netbox` / `plan_offbox` output, and git-mount presence.
- [lifecycle.bats](../../../test/unit/lifecycle.bats) — 16 tests covering `plan_recontain` / `plan_rebuild` / `plan_rm_container` / `plan_rm_image` for onbox, and the netbox/offbox equivalents including volume-populate steps.
- [smoke.bats](../../../test/unit/smoke.bats) — 6 harness self-tests (timeouts, tempdir, bats location, dispatcher error).

The unit suite mocks `podman` / `git` where needed (see [git-transport.bats](../../../test/unit/git-transport.bats)) and uses `container_running` / `container_exists` overrides to drive `container_sync_cmd` through both branches without actually invoking podman. This is clean and avoids the need for rootless-podman fixtures in unit tests.

### e2e suite (57 tests, all passing on a clean run)

The e2e suite drives real podman containers through `systemd-run --user --wait --collect --pipe` with `RuntimeMaxSec` and `KillMode=control-group`, matching [SPEC.md](../../../SPEC.md) §"testing". The suite covers:

- onbox: working directory, host-visible edits, internet access, read-only dotfiles mounts, dotfile copying, project-override-global, symlink invocation, long-form `--command`, interactive shell via `expect`, `-c --interactive`.
- netbox/offbox: internet access (netbox allows, offbox blocks), worktree isolation, onbox→netbox root inheritance, offbox→netbox volume copying, `--fresh`, `--inherit`, `--rm-container`, `--rm-image`, `--rebuild`.
- lifecycle: persistent container survival, `--read`/`--write`/`--port` mounts, `--rm-container`, `--recontain`, `--rebuild`.
- git-transport: host remote wiring, gitdir-volume freshness, container commits visible in volume, outside-gitdir refusal, submodule blocking, `fetch` (single + `--all`), bundle isolation (no config/hook leakage).
- merge/sync: `merge` (default, `<branch>`, `--all`), dirty-worktree warning, non-descendant refusal, detached-HEAD error, uninitialised-gitdir error, `sync` (default, `<branch>`, `--all`, stopped-container path), `merge --all` creating new local branches.

The `mk_talkbox` helper in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) neutralises the copied `defaults/read.mounts` / `write.mounts` / `ports` so e2e is hermetic — default mounts would otherwise reference host paths outside the test sandbox, and are already covered by unit tests. This is a thoughtful separation of concerns.

### canary / timeout harnesses

[test/canary/false.bats](../../../test/canary/false.bats) and [test/timeout/hang.bats](../../../test/timeout/hang.bats) verify that the harness correctly reports failures and kills hanging tests. Both fail as expected under `make test-canary` / `make test-timeout`. Good.

### test runner

[test/run-suite.sh](../../../test/run-suite.sh) is well-structured: it prefers `systemd-run` for suite-level timeout enforcement (with `RuntimeMaxSec` + `KillMode=control-group`) and falls back to `timeout(1)` when `systemd-run` is unavailable or fails to produce TAP output. Per-test timeouts are enforced via `BATS_TEST_TIMEOUT`. TAP output is parsed by [test/lib.bash](../../../test/lib.bash) into totals and failing-test names, written to a YAML run record at `.llm/gen/runs/<target>.gen.yaml`.

One minor robustness note: `parse_tap` in [test/lib.bash](../../../test/lib.bash) matches failing tests to their source file via the `# (in test file ...)` or `#  in test file ...` comment that bats emits. This is brittle — if bats changes its diagnostic format, the `FAIL_NAMES` entries would lose their file attribution (degrading to `(unknown) :: <name>`). This is a low-risk concern given bats' stable output format, but worth noting.

## observations (not filed as issues)

These are stylistic or theoretical observations that do not represent bugs or spec violations.

### `parse_onbox_options` is misleadingly named

[lib/options.sh](../../../lib/options.sh) defines `parse_onbox_options` and uses `ONBOX_*` variable names for all three containers (onbox, netbox, offbox). The dispatcher in [talkbox.sh](../../../talkbox.sh) calls `parse_onbox_options` for all three. The name is historical (onbox was the first container implemented) and the function is container-agnostic. Renaming to `parse_talkbox_options` / `TALKBOX_*` would improve clarity but is a large mechanical change.

### `execute_fetch_plan` is brittle

[lib/git.sh](../../../lib/git.sh) `execute_fetch_plan` splits the fetch plan by detecting `git` immediately followed by `fetch` in the plan array. This works because the podman command's internal `git bundle create` has `git` followed by `bundle`, not `fetch`. If the plan structure changes (e.g. a future `git fetch` is added to the podman command), the splitter could misbehave. A more robust approach would use explicit markers/delimiters in the plan array, but the current implementation is correct for the existing plan shape.

### `run_onbox` / `run_netbox` / `run_offbox` stop with `-t 1`

The 1-second stop grace period is aggressive. A process mid-write could lose data. This is a deliberate trade-off (fast container recycling) and is unlikely to cause issues in practice for interactive/coding-agent use, but a larger value (e.g. `-t 5`) would be safer.

### `run_onbox` / `run_netbox` / `run_offbox` duplicate exec logic

The three functions share an identical `exec_args` + `podman exec` + `podman stop` block. This could be factored into a shared helper, but the duplication is small (≈10 lines each) and the functions are otherwise clear.

### Containerfile uses `debian:trixie-slim`

`trixie-slim` is a rolling release tag. Pinning to a specific version (e.g. `debian:trixie-20240901-slim`) would improve reproducibility but at the cost of needing periodic manual updates. Acceptable for a development tool.

### `.bashrc` is host-quality, not container-quality

[defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) is a rich personal bashrc with many git aliases. This is fine for the project author's use but may be surprising for other users who clone the repo. The undefined colour variables (`$dim`, `$teal`, `$blue`, `$reset`) are a minor cosmetic issue — filed separately.

### Options parser silently ignores unexpected positionals after `fetch`

`onbox fetch mybranch` parses `mybranch` into `ONBOX_COMMAND`, which the fetch action ignores. No error or warning is emitted. This is a minor UX issue — the user gets no feedback that the positional was meaningless.

## verdict

The repository is well-organised, the implementation is faithful to the specification, and the test suite is thorough. The filed issues (README `openbox`/`onbox` mismatch, e2e port-test TOCTOU race, `.bashrc` undefined colours) are minor and do not affect the core functionality. The plan/execute pattern is consistently applied to lifecycle verbs; the normal-run path's inline approach is a reasonable stylistic choice. The git-transport layer is correct and well-tested (see the [dedicated review](git-transport-review.gen.md)). Overall, the codebase is in good shape.
