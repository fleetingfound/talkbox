# Review: talkbox repository — implementation, tests and harness

## scope

This review covers the overall correctness, organization, conciseness, understandability and quality of the talkbox implementation and its test suite. It complements the focused [git-transport review](git-transport-review.gen.md) by assessing the remaining layers: the dispatcher, the option/mount/port parsers, the container planners and lifecycle verbs, the image/entrypoint, and the test harness. The git-transport layer is summarised here only where it intersects with the overall assessment.

## verification performed

- `make lint` — clean (ShellCheck 0.10.0).
- `make test-unit` — 170 tests, 170 pass, 0 fail, 0 skip.
- `make test-e2e` — 60 tests, 60 pass, 0 fail, 0 skip.
- Manual empirical probes of `--rm-container`, `--recontain`, and option parsing edge cases (see [issues found](#issues-found)).

## organization

The implementation is cleanly modularised into focused files under [lib/](../../../lib/), matching the structure prescribed by [SPEC.md](../../../SPEC.md) §"implementation":

| file | responsibility |
|------|----------------|
| [lib/common.sh](../../../lib/common.sh) | `die()` and `trim()` utilities. |
| [lib/naming.sh](../../../lib/naming.sh) | pure naming helpers (slugs, volume/image names). |
| [lib/options.sh](../../../lib/options.sh) | argument parsing. |
| [lib/mounts.sh](../../../lib/mounts.sh) | mount-file/CLI parsing, depth ordering, dedup, volume-name emission. |
| [lib/ports.sh](../../../lib/ports.sh) | ports-file/CLI parsing and dedup. |
| [lib/git.sh](../../../lib/git.sh) | host-side git classification, submodule absorption, `fetch`/`merge`/`sync` actions. |
| [lib/merge.sh](../../../lib/merge.sh) | location-agnostic `custom_merge()` (sourced on host and in containers). |
| [lib/containers.sh](../../../lib/containers.sh) | image build, container planners, lifecycle verbs, volume population, sync execution. |
| [talkbox.sh](../../../talkbox.sh) | dispatcher routing `onbox`/`netbox`/`offbox` to the onbox/sandbox actions. |
| [image/Containerfile](../../../image/Containerfile) | shared `talkbox/base:latest` image. |
| [image/entrypoint.sh](../../../image/entrypoint.sh) | dotfile application, gitdir-volume initialisation, command execution. |

Each file has a single, well-delimited responsibility. The dispatcher ([talkbox.sh](../../../talkbox.sh)) is only 120 lines and does little beyond sourcing the modules and routing the verb to the right `run_*` executor. The naming module is pure (no side effects, no I/O), making it trivially testable. This is a good separation.

The largest file is [lib/containers.sh](../../../lib/containers.sh) at 789 lines. It concentrates all three container types' planners, populate helpers, lifecycle verbs and executors. There is some structural duplication between the `onbox`/`netbox`/`offbox` planner triples and the `recontain`/`rebuild`/`rm-container`/`rm-image` verb triples (e.g. the pasta-network/GPU/dotfiles-mount block is repeated three times across `plan_onbox`/`plan_netbox`/`plan_offbox`). This is acceptable for clarity — each planner reads top-to-bottom without indirection — but it is the most obvious candidate for future consolidation if the file grows further.

## conciseness

The code is reasonably concise. Bash idioms are used appropriately:

- `local -n` namerefs for array passing (the `# shellcheck disable=SC2178` / `SC2034` suppressions are correctly scoped).
- `printf -v port_list '%s,' "${_ports[@]}"; port_list="${port_list%,}"` for comma-joined port lists.
- The mount dedup-and-depth-order pass in `mount_entries` is compact (~20 lines) and uses associative arrays and `mapfile`+`sort` idiomatically.

Comments are absent per the project convention (AGENTS.md: "Do not include comments in code"), with the exception of `# shellcheck disable=` pragmas and one comment in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) explaining the GPU shim. This is consistent with the convention.

## understandability

Function names are descriptive and follow a consistent verb-noun pattern (`plan_*`, `run_*`, `container_*`, `volume_*`, `git_*`). The plan/execute separation in [lib/containers.sh](../../../lib/containers.sh) makes the container-creation logic easy to trace: `plan_*` functions build a flat `argv`-style array, `execute_plan` runs it. The two-array `plan_fetch` design (`bundle_cmd` + `fetch_cmd`) is similarly clear.

The `mount_entries` dedup logic is the densest passage in the codebase. It iterates the spec list in reverse to keep the last-seen dest (last-wins semantics), then sorts by path depth. This matches the spec's "shallower to deeper" requirement. The unit tests in [test/unit/mounts.bats](../../../test/unit/mounts.bats) pin this behaviour precisely.

## correctness

The core paths are correct and spec-faithful:

- **Mounts**: read-only bind-mounts for `onbox`/`netbox`/`offbox`; read-write bind-mounts for `onbox`; named volumes for `netbox`/`offbox` write mounts. The `$PROJECT`/`$HOME`/`~` expansion and default-dest derivation match the spec. Depth ordering and dedup are correct and tested.
- **Networking**: `pasta` with `-T,<port>` for `onbox`/`netbox`; `pasta` with `-T,<port>,-i,lo,-I,talkbox0` for `offbox`. `--cap-drop=NET_ADMIN`/`NET_RAW` applied to all three. Verified by unit tests and the e2e "offbox blocks internet access" test.
- **User mapping**: `--userns=keep-id:uid=1000,gid=1000` on all containers.
- **Inheritance**: `inherit_source` correctly implements the `onbox`→`netbox`→`offbox` default chain, `--fresh`, and `--inherit <source>` with base-image fallback when the source container does not exist. Verified by unit tests and the e2e `--inherit`/`--fresh` tests.
- **Git transport**: see the [git-transport review](git-transport-review.gen.md) — all five prior observations are now resolved.
- **GPU**: `--device nvidia.com/gpu=all --group-add keep-groups` appended when `TALKBOX_GPU=yes`. Verified by the GPU-shim e2e tests (which test argument emission without requiring a GPU).

The `entrypoint.sh` correctly applies global then project dotfiles (project overrides global), initialises a fresh git repository in the gitdir volume wired to the `host` remote at `/host/git/`, and performs an initial `git fetch host` + `git reset --mixed` to connect the worktree to the host history. The e2e tests confirm dotfile override, host-remote wiring, gitdir-volume freshness (not a copy of the host git dir), and the initial-fetch connection.

## test quality

The test suite is comprehensive and well-structured:

- **170 unit tests** across 8 files covering naming, options, mounts, ports, containers, lifecycle, netbox/offbox planning, git helpers, merge logic and git-transport helpers. Unit tests stub `podman`/`git` where needed via function overrides and run without `systemd-run`.
- **60 e2e tests** across 5 files exercising the full `talkbox.sh` → `podman` → container flow, including interactive sessions driven by `expect`, the `--port` host-HTTP-server probe, the GPU-shim argument capture, and the git-transport `fetch`/`merge`/`sync` round-trips.
- **Harness**: [test/runner.mk](../../../test/runner.mk), [test/run-suite.sh](../../../test/run-suite.sh) and [test/lib.bash](../../../test/lib.bash) provide suite-level (`systemd-run` + `RuntimeMaxSec`) and per-test (`BATS_TEST_TIMEOUT`) timeouts, TAP parsing, YAML run records, and `test-canary`/`test-timeout` sentinel suites. The `timeout(1)` fallback handles environments without `systemd-run`.
- Every e2e test that invokes `podman` or `talkbox.sh` goes through the `sdrun` helper ([test/e2e/helpers.bash](../../../test/e2e/helpers.bash)) which wraps the command in `systemd-run --user` with `RuntimeMaxSec` and `KillMode=control-group`, satisfying the spec's safety requirement.
- The e2e `mk_talkbox` helper copies the implementation into a temp dir and neutralises the default mounts/ports files, making the e2e suite hermetic.

Coverage gaps that remain (none are spec violations, all are lower-priority paths):

- `netbox merge` / `offbox merge` / `netbox sync` / `offbox sync` are not exercised in e2e (only `onbox merge`/`sync`). The logic is shared via `run_merge`/`run_sync` parameterised by container, so the risk is low, but a netbox/offbox round-trip e2e test would close the gap.

## issues found

Three new issues were identified during this review (see the [issue index](../issues/INDEX.gen.md)):

1. **[Lifecycle verbs leave named volumes orphaned and reuse stale volumes on recreate](../issues/lifecycle-verbs-leave-named-volumes-orphaned.gen.md)** — `--rm-container`, `--recontain` and `--rebuild` rely on `podman rm -f --volumes` to remove named volumes, but podman only removes anonymous volumes this way. Explicitly-created named volumes (gitdir, worktree, write) survive and are orphaned by `--rm-container` and silently reused by `--recontain`/`--rebuild`. This is a spec violation ("removes ... together with associated volumes" / "recreates ... all of its associated volumes"). Verified empirically. **Highest priority.**

2. **[Options requiring a value produce raw bash errors instead of talkbox messages](../issues/options-missing-value-unbound-variable.gen.md)** — `--read`/`--write`/`--port`/`--inherit` supplied as the final argument cause an `unbound variable` abort under `set -u` with a raw bash diagnostic instead of a `talkbox:`-formatted usage message. Minor UX issue.

3. **[`helpers.bash` files are excluded from `make lint` and `make format`](../issues/helpers-bash-excluded-from-lint-format.gen.md)** — the `SHELL_SCRIPTS` glob in [test/runner.mk](../../../test/runner.mk) matches `*.bats` but not `*.bash`, so [test/unit/helpers.bash](../../../test/unit/helpers.bash) and [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) escape shellcheck and shfmt. A formatting deviation and several shellcheck warnings are currently undetected. Minor harness gap.

## verdict

The implementation is well-organised, concise, readable and largely correct. The modular structure matches the spec's prescription, the plan/execute separation is clean, and the test suite (170 unit + 60 e2e, all passing, ShellCheck clean) provides strong coverage of the core and edge-case paths. The git-transport layer has been hardened since the original review — all five prior observations are resolved with dedicated tests.

The one substantive issue is the named-volume lifecycle: `--rm-container`/`--recontain`/`--rebuild` do not remove or recreate the explicitly-created named volumes, contradicting the spec and leaving orphaned volumes (and stale git history) behind. This should be addressed before relying on these verbs for cleanup. The other two issues are minor UX and harness-coverage gaps.
