# Tests: Phase 4 git integration (onbox/netbox/offbox) and fetch

Linked plan: [phase-4-git-integration-fetch.gen.md](../plans/phase-4-git-integration-fetch.gen.md)

Summary: this phase adds failing tests for the Phase 4 features the plan defers from Phase 3 — the per-container gitdir volume, the read-only host git folder mounted at `/host/git/`, the `host` remote and worktree wiring, the refusal when the host git directory lies outside `<project>`, submodule gitdir listing and in-container submodule blocking, the `fetch` subcommand with its `--all` flag, and the bundle-only git transport from container gitdir to host repository.

The tests pin the following interfaces, which the implementation must provide so that the tests pass once the plan is implemented:

- `lib/naming.sh`: `gitdir_volume <project> <container>` → `<project-slug>.<container>.gitdir` for `onbox`/`netbox`/`offbox`.
- `lib/options.sh`: `parse_onbox_options` additionally recognises the bare positional `fetch` as the fetch verb (field `ONBOX_VERB=fetch`) while `-c fetch` keeps `ONBOX_COMMAND=fetch`, and parses `--all` into the field `ONBOX_ALL` (default `no`).
- `lib/git.sh` (new):
  - Pure, no-`git` helpers over fixture paths: `git_tracked <project>` (predicate on `<project>/.git`), `resolve_git_dir <project>` (prints the resolved host git directory, following `gitdir:` files), `classify_git_dir <project>` (prints `inside`/`outside`/`none`), and `list_submodule_git_dirs <project>` (prints the submodule git directories under the top-level git dir's `modules/`).
  - `plan_fetch <out> <project> <container> <bundle_path>`: the fetch action plan — a `podman run --rm --network=none` helper that mounts the container's gitdir volume read-only and runs `git bundle create`, followed by a `git fetch <bundle_path>` whose refspec maps into `refs/remotes/<container>/*`.
- `lib/containers.sh`: the onbox/netbox/offbox argument assemblers append the git mounts (`-v <project>/.git:/host/git:ro` and `-v <gitdir_volume>:/working/<project-base>/.git`) when the project is git-tracked with the git directory inside `<project>`, and omit them otherwise; the netbox/offbox populate plans leave the gitdir volume empty (never populated from the host git folder).
- `image/entrypoint.sh` and `talkbox.sh` routing are exercised end-to-end: the container's gitdir is a fresh git directory wired to the `host` remote and connected to the host history, `onbox|netbox|offbox fetch [--all]` imports container commits via a bundle, and projects whose `.git` resolves outside `<project>` are refused.

## New tests

Unit tests (`test/unit/`):

- `test/unit/git.bats` (14 tests) - `git_tracked` (directory, gitdir-file, and absent cases), `resolve_git_dir` (plain `.git` directory, absolute and relative `gitdir:` files), `classify_git_dir` (`inside`, `outside` for a genuinely outside path, `outside` for a path-sibling like `<project>-other` to catch prefix confusion, and `none` for a non-git project), `list_submodule_git_dirs` (fixture `modules/` listing and the empty case), and `plan_fetch` (the no-network bundle-creation command mounting the gitdir volume read-only, and the `git fetch` refspec into `refs/remotes/<container>`). Pins the plan's "Pure helpers to (a) detect git-tracked status, (b) resolve and classify the host git directory (inside vs. outside `<project>`), (c) list submodule git dirs for absorption" and "the fetch action plan assembly (which git subcommands run and against which gitdir volume)", together with [SPEC.md §git as transport](../../../SPEC.md).
- `test/unit/naming.bats` (2 tests) - `gitdir_volume` derives `<project-slug>.<container>.gitdir` for `onbox`, `netbox` and `offbox`. Pins the plan's "add gitdir volume name derivation (`<project-slug>.<container>.gitdir`)".
- `test/unit/options.bats` (3 tests) - bare `fetch` is parsed as the fetch verb while `-c fetch` remains a command, `fetch --all` sets the verb and `ONBOX_ALL=yes`, and `--all` defaults to `no`. Pins the plan's "parse the `fetch` subcommand verb and its `--all` flag" and "the `fetch` verb and `--all` flag are exposed in the parsed record".
- `test/unit/containers.bats` (1 test) - `plan_onbox` for a git-tracked project emits `-v <project>/.git:/host/git:ro` and `-v talkbox-proj.onbox.gitdir:/working/talkbox-proj/.git`, and for a non-git project omits any git mount. Pins the plan's "asserting the onbox/netbox/offbox assembled `podman` argument lists include git mounts when applicable and exclude them when not".
- `test/unit/netbox-offbox.bats` (2 tests) - `plan_netbox`/`plan_offbox` for a git-tracked project emit the host-git and gitdir-volume mounts, while `plan_netbox_populate`/`plan_offbox_populate` never populate the gitdir volume (asserted via `array_has_none '<slug>.<container>.gitdir'` in the populate plan). Pins the plan's "the gitdir volume is created empty, not populated from `/host/git/`".

End-to-end tests (`test/e2e/git-transport.bats`, 9 tests):

- `onbox exposes the host git history as the host remote inside the container` - `git remote get-url host` inside the container prints `/host/git`.
- `onbox gitdir volume is a fresh git directory wired to the host remote, not a copy of the host git dir` - the `<slug>.onbox.gitdir` volume has a `config` with `[remote "host"]`/`/host/git` and lacks the host's `user.email` (`test@example.com`), showing it was `git init`-ed rather than copied from the host's `.git/`.
- `the onbox container working tree is connected to the host history via the initial fetch` - `git log` shows the host's `host-initial` commit and the container's `.git/config` contains `[remote "host"]` (connection via the fresh gitdir volume, not the host's bind-mounted `.git`).
- `a commit made in the container is visible in the container gitdir volume` - after an in-container commit, `refs/heads/<branch>` inside the gitdir volume holds a commit that differs from the host's `HEAD`.
- `onbox adds git mounts for a git-tracked project but not for a non-git folder` - a non-git folder runs with `/host/git` absent while the git-tracked project exposes it as a directory.
- `onbox, netbox and offbox refuse when the project .git points outside the project` - with `.git` replaced by a `gitdir:` file pointing outside, all three commands exit non-zero with a `talkbox:` error and no container is created.
- `git operations inside a submodule are blocked within the container` - after adding a submodule on the host, `git -C sub status` inside the container fails.
- `onbox fetch brings a container commit into the host repo via a bundle without transferring configs or hooks` - after an in-container commit and a container hook, `onbox fetch` makes the commit reachable at `refs/remotes/onbox/<branch>` while the host `user.email` stays `test@example.com` and no `container-hook`/`container-user` appear in the host git dir.
- `onbox fetch --all fetches from the onbox, netbox and offbox git histories` - with commits made in onbox, netbox and offbox, `onbox fetch --all` makes `refs/remotes/onbox/<branch>`, `refs/remotes/netbox/<branch>` and `refs/remotes/offbox/<branch>` each show their container's commit.

## Tests edited

- `test/lib.bash` - `parse_tap` now also recognises bats's helper-function failure line `#  in test file <file>, line <n>)` (continuation of `# (from function ...`), so that tests failing inside helper functions (e.g. `load_lib git.sh`, `array_contains`, `parse_onbox_options`) are recorded by name in the `fail:` field of the run records. Evidence: the plan requires the run record to capture the new failing tests, and bats 1.11 emits this continuation format for every failure that occurs inside a function (which the new `lib/git.sh` tests, absent until the plan is implemented, all do via `load_lib`).
- `test/unit/options.bats` - `setup()` now also initialises the new record field `ONBOX_ALL` (empty), and a file-level `# shellcheck disable=SC2030,SC2031` is added because the new tests read `ONBOX_VERB` across `@test` blocks (the same one-subshell-per-test model bats uses; shellcheck flags the intentional cross-test record reads). Evidence from the plan: "parse the `fetch` subcommand verb and its `--all` flag" and "exposed in the parsed record" alongside the existing fields.
- `test/unit/naming.bats` - added the two `gitdir_volume` tests described above; no existing assertions changed.
- `test/unit/containers.bats` - added the combined git-mount onbox test described above; no existing assertions changed.
- `test/unit/netbox-offbox.bats` - added the netbox/offbox git-mount and empty-gitdir-populate tests described above; no existing assertions changed.

## Tests removed

None. All pre-existing tests remain consistent with the plan: they pin the onbox/netbox/offbox argument-assembler outputs via presence checks that are unaffected by the additional git mounts (the unit setups use non-git fixture projects so no git mounts are emitted), and the e2e tests run on git-tracked projects but only assert file/volume/rootfs behaviour that the git mounts and wiring do not change. [SPEC.md §git as transport](../../../SPEC.md) states the git-related aspects are simply unavailable for non-git projects, and the plan defers `custom_merge()` and the `merge`/`sync` subcommands to Phase 5, which no existing test exercises.
