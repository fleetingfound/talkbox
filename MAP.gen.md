# Map

Core files implemented for the talkbox commands:

- [talkbox.sh](talkbox.sh) - the dispatcher which routes `onbox` (via `talkbox.sh onbox` or an `onbox` symlink) to the onbox action (assembling mounts/ports and dispatching the lifecycle verbs) and rejects the not-yet-implemented `netbox`/`offbox`.
- [lib/common.sh](lib/common.sh) - shared utilities module providing the `die()` helper (prints `talkbox: <message>` to stderr and exits with the given code) and `trim()` (strips leading/trailing whitespace).
- [lib/naming.sh](lib/naming.sh) - pure helpers producing `<project-base>`, `<project-slug>`, the shared base image name and the onbox container name `<project-slug>.onbox`.
- [lib/options.sh](lib/options.sh) - argument parsing for `onbox` (`-c`/`--command`, `--interactive`, `--noninteractive`, repeatable `--read`/`--write`/`--port`, and the `--recontain`/`--rebuild`/`--rm-container`/`--rm-image` lifecycle verbs), recording the selected command, interactive mode, verb and mount/port lists.
- [lib/mounts.sh](lib/mounts.sh) - parses mount files and CLI specs into depth-ordered, deduplicated `podman` `-v` argument lists per read/write mode, expanding `~`/`$HOME`/`$PROJECT` and deriving default dests.
- [lib/ports.sh](lib/ports.sh) - parses `defaults/ports` and CLI `--port` values into the deduplicated, ordered `pasta` `-T,<port>` token list.
- [lib/containers.sh](lib/containers.sh) - base image build, the `plan_onbox` persistent-container argument-list planner, the normal-run and lifecycle plan functions, the `execute_plan` runner, and the `run_*` executors which actually run `podman`.
- [image/Containerfile](image/Containerfile) - shared base image definition used to build `talkbox/base:latest`.
- [image/entrypoint.sh](image/entrypoint.sh) - in-container entrypoint which copies global then project dotfiles into `/home/dev/` and executes the user command or an interactive shell.

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
