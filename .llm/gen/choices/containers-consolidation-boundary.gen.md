# Choice: consolidation boundary and unit-test surface for `lib/containers.sh` (Phase 19)

## context

The [consolidation review](../reviews/containers-sh-consolidation-review.gen.md) identifies twelve function families duplicated across the `onbox`/`netbox`/`offbox` symmetry in [lib/containers.sh](../../../lib/containers.sh) (~40% of the file). The Phase 19 refactor is tagged `#flow/refactor`, so the revised unit tests may only exercise interfaces that exist today **and** survive the refactor.

Two surfaces satisfy that constraint, and the choice between them determines how much of the module's surface (and [talkbox.sh](../../../talkbox.sh)'s dynamic `"run_${container}_*"` dispatch) can be consolidated away:

- the `run_*` executors, invoked directly from a bats test with a logging `podman` shim on `PATH` (the pattern already used by the existing `run_onbox`/`run_netbox`/`run_offbox` ordering tests and the `run_rm_image` pruning tests);
- the `talkbox.sh` CLI, invoked as a subprocess with shims (the e2e suite's pattern).

Both produce the required "podman commands are constructed as they currently are" pinning, because both make the emitted `podman` command lines observable.

## options

### A. Executor-surface preservation (Recommended)

Consolidate everything *below* the executor layer: introduce the unified cores (`plan_container`, `plan_recreate`, unified rm planners, `create_sandbox`, `run_container`, `run_recreate`, unified rm executors, `pasta_net`, naming-dispatch helpers, `exec_in_container`/`stop_container`) and drop the per-container plan functions and create functions, but keep the fifteen existing `run_*` executor names ([talkbox.sh](../../../talkbox.sh)'s dispatch surface) as one-to-three-line delegates. [talkbox.sh](../../../talkbox.sh) is not modified.

The revised unit tests call the surviving `run_*` executors with a logging `podman` shim that forces the container-not-exists branch where the create path must be exercised, and assert on the emitted `podman` command lines.

- Pros: the review's recommended strategy adapted to drop the plan-level wrappers; no dispatcher churn; unit tests remain fast function-level bats tests with the established shim pattern; smallest risk for a behaviour-preserving refactor.
- Cons: ~15 small delegate functions remain (~40–60 lines), so the end state is not fully parameterized.

### B. Full parameterization with CLI-level unit tests

Replace the per-container executors with container-parameterized cores, update [talkbox.sh](../../../talkbox.sh) to call them with an explicit container argument instead of `"run_${container}_*"` dynamic dispatch, and revise the unit tests to invoke `talkbox.sh` itself with `podman`/git shims (requiring `mk_talkbox`-style temporary repo copies to control `TALKBOX_ROOT`, `defaults/` and option parsing).

- Pros: cleanest end state — no delegates, single dispatch path.
- Cons: the unit suite becomes a slower, more brittle duplicate of the e2e pattern, blurring the unit/e2e split described in [SPEC.md](../../../SPEC.md); substantially larger test rewrite and refactor scope for no behavioural benefit.

## recommendation

Option A: it delivers nearly all of the duplication reduction at a fraction of the risk, keeps the unit suite in its established form, and confines the refactor to [lib/containers.sh](../../../lib/containers.sh) and the tests.

## decision

**Selected: Option A — executor-surface preservation.** The fifteen `run_*` executor names survive as thin delegates over the unified cores, [talkbox.sh](../../../talkbox.sh) is not modified, and the revised unit tests exercise the executors with a logging `podman` shim, asserting the emitted `podman` command lines.
