# Choice: Planner-vs-executor project-dotfiles existence handling

## Context

[Review: Phase 1 onbox test suite](../reviews/phase-1-onbox-test-suite.gen.md) (item 8) flags a leaky abstraction in the current Phase 1 implementation:

- [lib/containers.sh](../../lib/containers.sh) `plan_onbox` always emits the `-v <project>/.dotfiles:/talkbox/dotfiles.project:ro` line, even when `.dotfiles` does not exist on the host.
- [lib/containers.sh](../../lib/containers.sh) `run_onbox` then filters that line out at execution time when `$project/.dotfiles` is not a directory.
- [SPEC.md](../../SPEC.md) (§onbox) says the project dotfiles folder is bind-mounted "when it exists on the host".

Consequently the unit test [test/unit/containers.bats](../../test/unit/containers.bats) (`onbox plan bind-mounts project dotfiles read-only`) asserts planner output that does not reflect what `podman run` actually receives. The planner's output is not the truthful podman argument list.

## Options

### Option A — Move the existence check into `plan_onbox` (Recommended)

Make `plan_onbox` consult the filesystem and omit the project-dotfiles `-v` line when `$project/.dotfiles` does not exist. The planner's output then becomes the exact argument list `podman run` receives, and the existing unit test (`onbox plan bind-mounts project dotfiles read-only`) becomes truthful without change. The filtering logic in `run_onbox` is removed, simplifying the executor to a thin pass-through.

- Pros: planner output is the single source of truth; `run_onbox` becomes a trivial executor; existing planner unit tests fully pin real podman behaviour; the abstraction is no longer leaky.
- Cons: `plan_onbox` gains a filesystem dependency, so unit tests that call it with a non-existent path (e.g. `/tmp/talkbox-proj`) would no longer emit the dotfiles line. The existing test would need its setup to create `$project/.dotfiles`, or assert the line's absence. This is a small implementation change beyond pure test-suite revision.
- Flow: this becomes a `#flow/redgreen` change (implementation + test adjustment) rather than pure pinning.

### Option B — Add a unit test documenting `run_onbox` filtering (test-only)

Leave `plan_onbox` and `run_onbox` as-is. Add a unit test that sources `lib/containers.sh` and asserts `run_onbox` (or a factored-out filtering helper) drops the project-dotfiles line when `$project/.dotfiles` is absent. Add a complementary test that the line is passed through when the directory exists. Optionally add a note to the planner unit test documenting that its output is pre-filtering.

- Pros: no implementation change; stays within "test suite revision" scope; explicitly documents the filtering behaviour that is currently implicit.
- Cons: the planner-vs-executor split remains a leaky abstraction; future phases (netbox/offbox, mount precedence) will likely want a single truthful planner output and may need to revisit this anyway.

## Recommendation

**Option A.** The planner-output-as-truth property is valuable and aligns with how Phase 2+ (mount files, `--read`/`--write`, precedence ordering) will need a single canonical planner. Doing it now while the surface is small avoids rework. The implementation change is minimal (move a one-line `[[ -d ... ]]` guard from `run_onbox` into `plan_onbox`).

## Selected option

**Option A** (selected by the user). The existence check for `$project/.dotfiles` moves from `run_onbox` into `plan_onbox`, making the planner's output the truthful `podman` argument list. `run_onbox` becomes a thin pass-through executor with no filtering. This is an implementation change (not purely test-suite), so the phase carrying it uses `#flow/redgreen`; the other shortcomings in this revision are pure test additions/tightenings and use `#flow/pin`.

## Related

- [Review: Phase 1 onbox test suite](../reviews/phase-1-onbox-test-suite.gen.md)
- [Issue: unit terminal-allocation assertion is too loose](../issues/terminal-allocation-assertion-too-loose.gen.md)
