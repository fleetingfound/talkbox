# Verdict: submodule e2e tests assert exact/empty `$output` that the SPEC-mandated `sdrun` harness makes unsatisfiable

Linked dispute: [submodule-tests-assert-noise-free-output.gen.md](../disputes/submodule-tests-assert-noise-free-output.gen.md)

Linked plan: [submodule-gitdir-inclusion-in-container.gen.md](../plans/submodule-gitdir-inclusion-in-container.gen.md) — summarised in one sentence: the plan adds an `include_host_modules` step to `image/setup.sh` (copy `/host/git/modules` into the container gitdir volume, rewrite each module's `core.worktree` to a gitdir-relative path resolved from `.gitmodules`, and make `objects/`/`refs/`/`packed-refs` non-writable) and revises the submodule e2e tests accordingly.

No new issue documents were created: the implementation claims in the dispute were independently validated (see Verification below) and the core implementation is correct; both failures were errors in the tests' assertions.

## Test: `superproject status and add succeed in the container with an absorbed submodule`

- Test file: [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats)
- Verdict: `BROKEN_TEST`

### Justification

The failing assertion `[[ -z "$output" ]]` (line 126) requires the bats `run` capture to be totally empty. That is unsatisfiable for any core implementation because SPEC.md ("testing") mandates the wrapper through which every podman-invoking command must pass:

> Any test which invokes `podman`, including those which call `talkbox.sh`, `onbox`, `netbox` or `offbox`, must be called via `systemd-run` with the options `RuntimeMaxSec` and `KillMode=control-group` passed via the flag `-p` in order to prevent commands from hanging indefinitely.

[sdrun](../../../test/e2e/helpers.bash) implements this as `systemd-run --user --wait --collect --pipe …`; `systemd-run --pipe --wait` writes the unit-lifecycle lines (`Running as unit: …`, `Finished with result: …`, `Main processes terminated with: …`, `Service runtime: …`, `CPU time consumed: …`, `Memory peak: …`) to stderr, which bats' merged-mode `run` folds into `$output` (empirically confirmed on this system: systemd 257, bats 1.11.1 — a bare `sdrun true` capture contains exactly these six lines). Additionally, the first `run_talkbox` in a test creates the container, and [lib/containers.sh](../../../lib/containers.sh) `execute_plan`/`run_container` invoke `podman volume create`/`podman create`/`podman start` without output redirection, so their stdout (volume name, container ID, container name) is captured too. An isolated replication of the test body shows the git commands themselves exit 0 printing nothing (status=0, `$output` consisting entirely of the above harness noise), i.e. the asserted behaviour holds and only the assertion's shape is unsatisfiable.

The plan requires (its "Tests" section) that the suite exercise "superproject status succeeds" — nothing in SPEC.md or the plan requires empty capture, and every other e2e test asserts with noise-tolerant substring checks (e.g. `[[ "$output" == *'working tree clean'* ]]` in the passing sibling tests in the same file).

### Repair

The empty-output intent (clean superproject tree: `git status --porcelain` and `git add -A --dry-run` print nothing) is preserved exactly by delimiting the git output with markers in the in-container command — `echo STATUS_BEGIN && git status --porcelain && git add -A --dry-run && echo STATUS_END` — and asserting the markers are adjacent: `[[ "$output" == *"STATUS_BEGIN"$'\n'"STATUS_END"* ]]`. Any git output (a porcelain status line, an `add '…'` dry-run line, or a stderr warning) breaks the adjacency and fails the test, while the unavoidable harness noise outside the marker pair is tolerated. The exit-status assertion and the subsequent dirt-detection phase (`' M sub'` substring check) are unchanged.

## Test: `the container resolves an absorbed module gitdir against the container submodule path`

- Test file: [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats)
- Verdict: `BROKEN_TEST`

### Justification

The failing assertion `[[ "$output" == "/working/$PROJECT_BASE/sub" ]]` (line 142) requires the bats `run` capture to consist of exactly the single toplevel line. This is unsatisfiable for the same SPEC-mandated reason as above: the `sdrun`-wrapped `run_talkbox` capture always contains the systemd-run unit-lifecycle lines and, on the first run per test, the podman container-creation stdout. An isolated replication shows the expected line `/working/<project-base>/sub` is present in the capture with exit status 0 — the implementation behaviour the test intends to pin (the `core.worktree` rewrite in [image/setup.sh](../../../image/setup.sh) `include_host_modules` resolving `submodule.<name>.path` from `.gitmodules` over the host-planted absolute `core.worktree`) holds, including for a name≠path module.

### Repair

The exactness is preserved rather than relaxed to a bare substring: `grep -Fxq "/working/$PROJECT_BASE/sub" <<<"$output"` asserts that some line of the capture is exactly `/working/<project-base>/sub`, so a wrong resolution (e.g. a double-prefixed path or the host-side absolute path) still fails the test, while the surrounding harness noise is tolerated. The suite already uses `grep -q` assertions for exactness (e.g. `grep -q '\[remote "host"\]'` in the same file).

## Verification

- The dispute's implementation claims were independently validated with an isolated replica of the test bodies outside the suite: `git status --porcelain && git add -A --dry-run` exits 0 producing no git output inside the container, and `git -C sub rev-parse --show-toplevel` prints `/working/<project-base>/sub` for a name≠path module whose host-side `core.worktree` was set to an absolute host path (the rewrite overrides it).
- After repair: `make lint` and `make format` pass; `make test-unit` — `total=307 pass=307 fail=0 skip=0 exit=0`; `make test-e2e` — `total=81 pass=81 fail=0 skip=0 exit=0` (including the two repaired tests).
- Every remaining failure (none) would be attributable to the project implementation rather than to a test error or timeout.
