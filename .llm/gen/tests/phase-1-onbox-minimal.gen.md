# Tests: Phase 1 onbox minimal working application

Linked plan: [phase-1-onbox-minimal.gen.md](../plans/phase-1-onbox-minimal.gen.md)

Summary: this phase implements the smallest externally-usable slice of `SPEC.md` — the `onbox` command creating a container from the shared base image with internet access, a read-write host worktree bind-mount, dotfiles applied on entry, and an interactive shell by default (plus `-c`/`--command` execution).

## New tests

31 new tests were written, all of which fail until the plan is implemented because the files under test (`talkbox.sh`, `lib/naming.sh`, `lib/options.sh`, `lib/containers.sh`, `image/entrypoint.sh`) do not yet exist. They are expected to pass once the plan document is implemented.

Unit tests (`test/unit/`):

- `test/unit/helpers.bash` - shared `load_lib` helper which sources a `lib/*.sh` file, failing each test with a clear message when the library is not yet implemented.
- `test/unit/naming.bats` - 7 tests for `lib/naming.sh`: `project_base` (basename, trailing-slash handling), `project_slug` (lowercasing, non-alphanumeric to hyphens, run collapsing, already-slugged identity) and `base_image_name` (non-empty, stable). These capture the plan's "pure helpers for `<project-base>`, `<project-slug>`, base image name".
- `test/unit/options.bats` - 6 tests for `lib/options.sh`: `parse_onbox_options` records the selected command and interactive mode in `ONBOX_COMMAND` / `ONBOX_INTERACTIVE` for default shell, `-c`, `--command`, `-c --interactive`, `-c --noninteractive` and flag-order independence. These capture the plan's `-c`/`--command`/`--interactive`/`--noninteractive` parsing.
- `test/unit/containers.bats` - 11 tests for `lib/containers.sh`: `plan_onbox <project> <command> <interactive>` assembles the onbox `podman` argument list — workdir `/working/<project-base>/`, `--userns=keep-id:uid=1000,gid=1000`, `--network=pasta` (no `-T` host-port forwarding), `--cap-drop=NET_ADMIN` / `--cap-drop=NET_RAW`, read-write worktree bind-mount, read-only global and project dotfiles bind-mounts, the shared base image, terminal allocation for interactive and none for noninteractive, and command appending.

End-to-end tests (`test/e2e/`):

- `test/e2e/helpers.bash` - shared helpers: `sdrun` wraps each podman-invoking call in the required `systemd-run` envelope (`RuntimeMaxSec`, `KillMode=control-group`, `--pipe`), `mk_project` creates a temporary git repo stand-in for `<project>`, `mk_talkbox` builds a throwaway talkbox checkout with a fake `defaults/dotfiles/`, and `run_onbox_noninteractive` runs `talkbox.sh onbox -c --noninteractive` from the project directory.
- `test/e2e/onbox.bats` - 7 tests invoking `talkbox.sh onbox` against a temporary git repo: working directory is `/working/<project-base>/`, files written in the container appear on the host worktree, internet access works via a bounded `curl`, fake global dotfiles land in `/home/dev/`, project `.dotfiles/` override global dotfiles, symlinked `onbox` invocation works, and an `expect`-driven interactive session starts a shell and exits via `exit`.

## Tests edited

None. The existing harness smoke tests (`test/unit/smoke.bats`, `test/e2e/smoke.bats`) remain unchanged and still pass.

## Tests removed

None. No pre-existing tests were inconsistent with the plan document, `SPEC.md` or `SPEC.gen.md`, so nothing was removed.

## Interface contract defined by these tests

Because `lib/*.sh` and `talkbox.sh` do not exist yet, the tests fix the minimal interface the implementation must provide:

- `lib/naming.sh`: `project_base <project>` and `project_slug <project>` print the project base name and hyphenated alphanumeric slug; `base_image_name` prints the shared base image name.
- `lib/options.sh`: `parse_onbox_options "$@"` sets `ONBOX_COMMAND` (empty when no `-c`/`--command`) and `ONBOX_INTERACTIVE` (`yes` by default / with `--interactive`, `no` with `--noninteractive`).
- `lib/containers.sh`: `plan_onbox <project> <command> <interactive>` prints the assembled onbox `podman` argument list, one argument per line.
- `talkbox.sh onbox` (also via an `onbox` symlink) runs the container, and `image/entrypoint.sh` copies global then project dotfiles into `/home/dev/` before executing the command/shell.
