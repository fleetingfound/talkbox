# Dispute: submodule e2e tests assert exact/empty `$output` that the SPEC-mandated `sdrun` harness makes unsatisfiable

Linked plan: [submodule-gitdir-inclusion-in-container.gen.md](../plans/submodule-gitdir-inclusion-in-container.gen.md)

The plan's implementation ([image/setup.sh](../../../image/setup.sh) `include_host_modules`) is complete and demonstrably correct: an isolated replica of the two disputed test bodies (identical fixtures, commands and helpers, run outside the suite) shows the expected command behaviour inside the container — superproject `git status --porcelain && git add -A --dry-run` exits 0 producing no git output, and `git -C sub rev-parse --show-toplevel` prints `/working/<project-base>/sub` for a module whose host-side `core.worktree` was set to an absolute host path. Both disputed tests fail only on assertions about the *shape* of `$output`, which no core implementation can satisfy.

## Root cause of the unsatisfiable assertions

1. SPEC.md ("testing") requires every podman-invoking test to run through `systemd-run` with `-p RuntimeMaxSec=… -p KillMode=control-group`. [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) implements this in `sdrun` as `systemd-run --user --wait --collect --pipe …`, and `run_talkbox`/`run_onbox_noninteractive` wrap every container invocation in `sdrun`.
2. `systemd-run --pipe --wait` prints `Running as unit: …` and the `Finished with result: …` block to **stderr** (verified separately: the lines disappear under `2>/dev/null`).
3. bats `run` executes in merged mode, folding stderr into `$output`; additionally the first run per test performs container creation whose `podman volume create`/`podman create`/`podman start` print the volume name, container ID and container name on stdout.
4. Therefore `$output` of every `run_talkbox` invocation always contains the unit-lifecycle lines plus first-run podman noise, regardless of what the in-container command prints. Every other test in the suite acknowledges this noise floor by using substring assertions (`[[ "$output" == *'…'* ]]`); the two disputed tests do not.

## Disputed tests

### `superproject status and add succeed in the container with an absorbed submodule`

- Test file: [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats) (line 126)
- Failing assertion: `[[ -z "$output" ]]` after `run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git status --porcelain && git add -A --dry-run'`
- Exact failure output (full-suite run and isolated re-run, identical):

```
not ok 16 superproject status and add succeed in the container with an absorbed submodule
# (in test file test/e2e/git-transport.bats, line 126)
#   `[[ -z "$output" ]]' failed
```

- Replicated `$output` for the disputed run (exit status 0; the git commands themselves print nothing — the capture is entirely harness noise):

```
Running as unit: run-p1200599-i5394851.service; invocation ID: 55263707a634474f913613df53184023
tmp-5c2xk22e9p.onbox.gitdir
9e4a938ee4a07734d8b4c3ecd6e3eb99b9f8fcbc1fb734a947f0c2c7147af2b1
tmp-5c2xk22e9p.onbox
Finished with result: success
Main processes terminated with: code=exited, status=0/SUCCESS
Service runtime: 769ms
CPU time consumed: 593ms
Memory peak: 53.3M (swap: 0B)
```

- Related core files: [image/setup.sh](../../../image/setup.sh) (`include_host_modules` — module copy, `core.worktree` rewrite, targeted read-only permissions).

### `the container resolves an absorbed module gitdir against the container submodule path`

- Test file: [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats) (line 142)
- Failing assertion: `[[ "$output" == "/working/$PROJECT_BASE/sub" ]]` after `run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git -C sub rev-parse --show-toplevel'`
- Exact failure output (full-suite run and isolated re-run, identical):

```
not ok 17 the container resolves an absorbed module gitdir against the container submodule path
# (in test file test/e2e/git-transport.bats, line 142)
#   `[[ "$output" == "/working/$PROJECT_BASE/sub" ]]' failed
```

- Replicated `$output` for the disputed run (exit status 0; the expected line **is present**, surrounded by harness noise):

```
Running as unit: run-p1201014-i5395266.service; invocation ID: 1d739bde56f548f5a14bb14798616b58
tmp-ks1ezbuaoa.onbox.gitdir
a6f084467a53e78e358d36afd8a1fae7b193f8515be60ff2c5a5698c327b6560
tmp-ks1ezbuaoa.onbox
/working/tmp.KS1eZbUaOA/sub
Finished with result: success
Main processes terminated with: code=exited, status=0/SUCCESS
Service runtime: 968ms
CPU time consumed: 665ms
Memory peak: 55.5M (swap: 0B)
```

- Related core files: [image/setup.sh](../../../image/setup.sh) (`include_host_modules` — the rewrite resolves `submodule.module-name.path` from the worktree's `.gitmodules` and overrides the absolute host path the test plants).

## Justification

The plan requires (its "Tests" section) that the suite exercise "superproject status succeeds; submodule write prevented, submodule read works" using the e2e harness conventions (`run_talkbox`). The superseded-module test on lines 101–115 ("submodule reads work in the container while submodule history writes are prevented") and the refresh test on lines 148–169 follow those conventions with substring assertions and **pass** (as do all 307 unit tests). The two disputed tests deviate from the harness conventions by asserting on the entirety of `$output` (`-z` and exact equality), which is impossible because the SPEC-mandated `sdrun` wrapper injects `systemd-run` unit-lifecycle messages into every capture through bats' merged stderr. This is an error in the tests' implementation, not in the core: the demonstrated captures show the asserted behaviour holding (exit 0, empty git output, correct `/working/<base>/sub` line) with only harness noise around it. Suggested fix consistent with the rest of the suite: replace line 126's `[[ -z "$output" ]]` with a substring-style check (e.g. `[[ "$output" != *'fatal'* ]]`), and line 142's exact equality with `[[ "$output" == *"/working/$PROJECT_BASE/sub"* ]]`. The subsequent dirt-check phase of the first disputed test (`[[ "$output" == *' M sub'* ]]`, line 129) is substring-based and passes.
