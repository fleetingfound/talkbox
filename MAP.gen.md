# Map

Core files implemented for the talkbox commands:

- [talkbox.sh](talkbox.sh) - the dispatcher which routes `onbox` (via `talkbox.sh onbox` or an `onbox` symlink) to the onbox action and `netbox`/`offbox` to the shared sandbox action (assembling mounts/ports, preparing the host git repo, dispatching the lifecycle verbs and the `fetch` subcommand).
- [lib/common.sh](lib/common.sh) - shared utilities module providing the `die()` helper (prints `talkbox: <message>` to stderr and exits with the given code) and `trim()` (strips leading/trailing whitespace).
- [lib/naming.sh](lib/naming.sh) - pure helpers producing `<project-base>`, `<project-slug>`, the shared base image name, the onbox/netbox/offbox container names, the netbox/offbox worktree, write-volume, root-image and gitdir-volume names, and the `<dest-slug>` derivation for a dest path.
- [lib/options.sh](lib/options.sh) - argument parsing for `onbox`/`netbox`/`offbox` (`-c`/`--command`, `--interactive`, `--noninteractive`, repeatable `--read`/`--write`/`--port`, `--fresh`, `--inherit <source>`, `--all`, the `fetch` subcommand verb, and the `--recontain`/`--rebuild`/`--rm-container`/`--rm-image` lifecycle verbs), recording the selected command, interactive mode, verb and mount/port/inheritance selections.
- [lib/mounts.sh](lib/mounts.sh) - parses mount files and CLI specs into depth-ordered, deduplicated `podman` `-v` argument lists per read/write mode, expanding `~`/`$HOME`/`$PROJECT` and deriving default dests; `mount_volume_args` additionally emits netbox/offbox write mounts as named volumes (`<slug>.<container>.write.<dest-slug>`).
- [lib/ports.sh](lib/ports.sh) - parses `defaults/ports` and CLI `--port` values into the deduplicated, ordered `pasta` `-T,<port>` token list.
- [lib/containers.sh](lib/containers.sh) - base image build, the `plan_onbox`/`plan_netbox`/`plan_offbox` persistent-container argument-list planners (with conditional git mounts), the lifecycle plan functions, the `execute_plan` runner, and the `run_*` executors which actually run `podman`, including the root-image inheritance planner (`inherit_source`), the no-network volume-population planner (`plan_volume_populate`) and the netbox/offbox volume population and lifecycle verbs.
- [lib/git.sh](lib/git.sh) - host-side git helpers: `git_tracked`/`resolve_git_dir`/`classify_git_dir` (inside/outside/none), `list_submodule_git_dirs` (submodule absorption enumeration), `git_mounts_enabled` (git-mount predicate), `refuse_outside_gitdir`/`absorb_submodules`/`prepare_git_host` (host-side git preparation), and the `fetch` action (`plan_fetch` assembles the no-network gitdir-bundle `podman run` plus the host `git fetch` into `refs/remotes/<container>`, executed by `execute_fetch_plan` from `run_fetch`).
- [image/Containerfile](image/Containerfile) - shared base image definition used to build `talkbox/base:latest`.
- [image/entrypoint.sh](image/entrypoint.sh) - in-container entrypoint which copies global then project dotfiles into `/home/dev/`, initializes a fresh git repository in the gitdir volume when present (wiring the `host` remote at `/host/git/`, setting the working tree, and performing an initial `git fetch host` + `git reset --mixed` to connect to the host history), and executes the user command or an interactive shell.

Core files implemented for the test harness:

- [Makefile](Makefile) - top-level makefile which includes the test harness definitions from `test/runner.mk`.

The remaining harness files live under `test/`:

- [test/runner.mk](test/runner.mk) - defines the `test-unit`, `test-e2e`, `test-canary` and `test-timeout` targets, the `GLOBAL_TEST_TIMEOUT` and `INDIVIDUAL_TEST_TIMEOUT` defaults, and the `lint` and `format` targets.
- [test/run-suite.sh](test/run-suite.sh) - runs a bats suite under the global timeout (via `systemd-run` with a `timeout(1)` fallback), enforces the individual timeout via `BATS_TEST_TIMEOUT`, parses the TAP output and writes the run record for the suite.
- [test/lib.bash](test/lib.bash) - helper functions that parse bats TAP output into totals and failing test names, escape YAML single quotes, and write the YAML run record.
- [test/unit/smoke.bats](test/unit/smoke.bats) - unit smoke tests which verify harness basics such as the timeout environment variables, per-test temporary directories and the bats runner.
- [test/e2e/smoke.bats](test/e2e/smoke.bats) - end-to-end smoke tests which verify the harness from the outside, e.g. that `make` exposes the four test targets and that the runner writes run records.
- [test/canary/false.bats](test/canary/false.bats) - canary tests which intentionally assert something false and are expected to fail under `make test-canary`.
- [test/timeout/hang.bats](test/timeout/hang.bats) - timeout canary test which runs a non-terminating command and is expected to fail under `make test-timeout`.
