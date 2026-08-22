# Tests: Phase 2 mounts, ports and onbox lifecycle management

Linked plan: [phase-2-mounts-ports-lifecycle.gen.md](../plans/phase-2-mounts-ports-lifecycle.gen.md)

Summary: this phase adds failing tests for the Phase 2 features the plan defers from Phase 1 — the read/write mount files, the port file, their `--read`/`--write`/`--port` CLI overrides, mount precedence ordering, the onbox image/container lifecycle verbs (`--recontain`, `--rebuild`, `--rm-container`, `--rm-image`), and the transition of the normal `onbox` run from the ephemeral `podman run --rm` model to the persistent named-container model required by [SPEC.md §image and container management](../../../SPEC.md).

The tests pin the following interfaces, which the implementation must provide so that the tests pass once the plan is implemented:

- `lib/naming.sh` `onbox_container_name <project>` prints `<project-slug>.onbox`.
- `lib/mounts.sh` `mount_args <out> <mode> <defaults_file> <project> <home> [cli_spec ...]` fills `<out>` (a nameref array) with the merged `-v` argument list for the mode (`read` adds `:ro`; `write` does not), depth-ordered shallow-to-deep by number of `<dest>` path segments, collapsing identical dests (last source wins), expanding `~`/`$HOME` (source and dest) and `$PROJECT` (dest) using the injected `<home>`/`<project>`, and deriving default dests `/host/read/<basename>` / `/host/write/<basename>`.
- `lib/ports.sh` `port_args <out> <defaults_file> [cli_port ...]` fills `<out>` with the deduplicated, ordered `-T,<port>` tokens (defaults file order first, then CLI additions).
- `lib/containers.sh` `plan_onbox <out> <project> <interactive> <read_mounts> <write_mounts> <ports>` appends the `podman create` argument list for the persistent container: `--name=<onbox_container_name>`, workdir, userns, `--network=pasta[:<pasta -T port list>]`, cap-drops, the worktree/dotfiles core mounts, the merged read/write mounts, `--interactive`/`--tty` when interactive, the image, and never `--rm`; the user command is not part of the create args.
- `lib/containers.sh` `plan_onbox_run <out> <project> <command> <interactive> <read_mounts> <write_mounts> <ports>` appends the normal-run invocation sequence `podman create` → `podman start` → (`podman exec <name> <command>` when a command is given).
- `lib/containers.sh` `plan_recontain <out> <project> <interactive> <read_mounts> <write_mounts> <ports>` (`rm` → `create` → `start`), `plan_rebuild` (`build` → `rm` → `create` → `start`), `plan_rm_container <out> <project>` (`rm --volumes`), and `plan_rm_image <out> <project> <in_use>` (`rmi` only when `in_use` is `no`).
- `lib/options.sh` parses the new repeatable `--read`/`--write`/`--port` flags and the lifecycle verbs into the record fields `ONBOX_READ`, `ONBOX_WRITE`, `ONBOX_PORT` (arrays) and `ONBOX_VERB` (empty by default).

## New tests

Unit tests (`test/unit/`):

- `test/unit/mounts.bats` (14 tests) - `mount_args` read/write default-dest derivation, both `<source> : <dest>` line forms (with and without spaces), blank/`#` line skipping, absent and empty defaults files, `~`/`$HOME`/`$PROJECT` placeholder expansion, default-file/CLI union, identical-dest collapse (last wins), shallow-to-deep nested-dest ordering, and read/write cross-mode independence. Pins [SPEC.md §mounts](../../../SPEC.md) (mount file format, default dests, placeholders, precedence) and the plan's `lib/mounts.sh` description.
- `test/unit/ports.bats` (6 tests) - `port_args` in-order parsing, blank/`#` skipping, absent/empty files, dedup, and default-file/CLI union. Pins [SPEC.md §network](../../../SPEC.md) (defaults/ports, `--port`, union) and the plan's `lib/ports.sh` description.
- `test/unit/lifecycle.bats` (5 tests) - `plan_recontain` (`rm create start`), `plan_rebuild` (`build rm create start` with `-t talkbox/base:latest` and the `Containerfile`), `plan_rm_container` (`rm --volumes <name>`), and `plan_rm_image` in-use guard (no `rmi` when the image is in use; `rmi <image>` when it is not). Pins the plan's "which `podman` subcommands and in what order for each verb, `--rm-image` in-use guard logic".
- `test/unit/containers.bats` (new tests) - `onbox plan names the persistent container <project-slug>.onbox` (`--name=talkbox-proj.onbox`), `onbox plan does not emit --rm for the persistent normal run`, `onbox plan applies default mounts and pasta -T ports` (assembling arrays via `mount_args`/`port_args` and asserting the merged `-v` entries and `--network=pasta:-T,8080,-T,9090`), and the two `plan_onbox_run` tests (create→start for an interactive shell; create→start→exec with the command as the last element).
- `test/unit/naming.bats` (2 tests) - `onbox_container_name` returns `<project-slug>.onbox` for a slugged and an un-slugged project path.
- `test/unit/options.bats` (6 tests) - repeatable `--read`/`--write`/`--port` recording, lifecycle-verb recognition (`ONBOX_VERB`), the empty default verb, and that a `--read` value is not consumed as the command.

End-to-end tests (`test/e2e/lifecycle.bats`):

- `onbox creates a persistent container that survives after the shell exits` - drives an interactive `onbox` session through `expect`, exits, and asserts the `<project-slug>.onbox` container still exists.
- `onbox -c <command> runs within the same persistent container` - writes a probe to the container root filesystem with one `-c --noninteractive` invocation and reads it back with a second, proving the same container is reused.
- `onbox --read exposes a read-only mount inside the container` - a `--read` file appears at `/host/read/<basename>` and is not writable.
- `onbox --write exposes a writable mount inside the container` - a file written to `/host/write/<basename>/` appears on the host.
- `onbox --port makes a host port reachable inside the container` - a host `python3 -m http.server` is reachable from the container via `http://127.0.0.1:<port>/marker` when `--port` is passed.
- `onbox --rm-container removes the persistent container` - the container exists after a `-c` run and no longer exists after `--rm-container`.
- `onbox --recontain recreates the container and starts it` - a root-filesystem probe written before `--recontain` is gone afterwards and a fresh `-c` command works.
- `onbox --rebuild rebuilds the base image and starts the container` - `--rebuild` succeeds on a fresh project and a subsequent `-c` command runs.

## Tests edited

- `test/unit/containers.bats` - every planner test is updated to the new `plan_onbox <out> <project> <interactive> <read_mounts> <write_mounts> <ports>` signature (the Phase-1 `rm` parameter and `<command>` position are retired). Evidence from the plan: "the Phase-1 `rm` planner parameter is retired in favour of the persistent model" and "a planner function returning the sequence of `podman` invocations for the normal run (create-if-not-exists + start, or exec for `-c` commands)"; [Choice: Planner array-population mechanism](../choices/planner-array-mechanism.gen.md) specifies "pre-parsed structured inputs (mount lists, port lists) must be passable to the planner as array arguments".
- `test/unit/options.bats` - `setup()` initialises the new record fields (`ONBOX_VERB`, `ONBOX_READ`, `ONBOX_WRITE`, `ONBOX_PORT`) alongside the Phase-1 fields. Evidence from the plan: "expose them in the structured record alongside the Phase-1 command/interactive fields".
- `test/e2e/onbox.bats` - `setup()`/`teardown()` now derive the project's `<project-slug>.onbox` container name and remove it after each test, because every `onbox` run now creates a persistent container. Evidence from the plan: "E2e test teardown must clean up persistent containers."
- `test/e2e/helpers.bash` - `mk_talkbox` now empties the copied `defaults/read.mounts`, `defaults/write.mounts` and `defaults/ports` so e2e remains hermetic. After the plan, "Default mounts and ports from `defaults/` are now applied (in addition to the Phase-1 core mounts)"; the shipped `defaults/read.mounts` references `~/.local/share/opencode/auth.json`, so leaving it would make every e2e run depend on a host file existing. Default mounts are covered by the unit tests; the plan's e2e list exercises the CLI `--read`/`--write`/`--port` instead. The helpers also gain `onbox_ctr_name` and `free_host_port` used by the new e2e tests.

## Tests removed

- `test/unit/containers.bats` - `onbox plan emits --rm so the container is removed after exit` and `onbox plan omits --rm when the rm input is no`. These pin the ephemeral `podman run --rm` model and the `rm` planner parameter, both of which the plan replaces: "the normal `onbox` run ... rather than an ephemeral `podman run --rm` container" and "The normal run no longer includes `--rm`; the Phase-1 `rm` planner parameter is retired in favour of the persistent model"; [SPEC.md §image and container management](../../../SPEC.md) now expresses removal as the explicit `onbox --rm-container` verb. They are superseded by `onbox plan does not emit --rm for the persistent normal run`.
- `test/unit/containers.bats` - `onbox noninteractive plan appends the command as the last element`. The command is no longer part of the `podman create` argument list because `onbox -c <command>` "runs the command within the existing container (creating it first if it does not exist)" via exec; the behaviour is superseded by the `plan_onbox_run` tests asserting `podman exec <name> <command>`.
