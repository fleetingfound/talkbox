# Choice: `execute_fetch_plan` boundary mechanism

## Context

`plan_fetch` in [lib/git.sh](../../../lib/git.sh) assembles a single flat array containing two logically distinct commands:

1. a no-network `podman run` that bundles the gitdir volume (`git bundle create`), and
2. a host-side `git fetch <bundle>` into `refs/remotes/<container>/*`.

`execute_fetch_plan` walks that array and splits it into the two commands by detecting the token `git` immediately followed by `fetch`. This works only because the podman command's internal `git` token is followed by `bundle`, not `fetch`. The splitter is coupled to the incidental shape of the plan rather than to an explicit structure, and would misbehave if a future plan step introduced another `git fetch` sequence. See the filed [issue](../issues/execute-fetch-plan-brittle-split.gen.md).

The callers are `run_fetch` and `run_merge`, both in [lib/git.sh](../../../lib/git.sh). `execute_fetch_plan` is the only consumer of `plan_fetch`'s output.

## Options

### Option A — Two-array output from `plan_fetch` (Recommended)

`plan_fetch` populates two caller-declared arrays: one for the podman bundle command and one for the host `git fetch` command. The callers (`run_fetch`, `run_merge`) run each command array in turn with a trivial `"$cmd1[@]"` / `"$cmd2[@]"` sequence. `execute_fetch_plan` is removed entirely.

**Pros:**
- Eliminates the splitter completely — there is no boundary to detect, because the two commands are structurally separate from the point of construction.
- Each command array is run directly (`"${cmd[@]}"`) with no re-parsing, exactly as the lifecycle `execute_plan` already runs podman commands.
- Smallest conceptual surface: the plan is just "two commands".
- Unit tests assert on the two arrays directly (the bundle command contains `podman run --network=none` + `git bundle create`; the fetch command contains `git fetch` + `refs/remotes/<container>`), which is more precise than asserting on log output.

**Cons:**
- Changes the signature of `plan_fetch` (two output namerefs instead of one), requiring updates to both callers and the unit test.
- Slightly diverges from the single-flat-array convention used by the lifecycle planners, though those planners split on the `podman` keyword (which `execute_plan` does) — a luxury unavailable here since the host command is `git`, not `podman`.

### Option B — Explicit delimiter token

`plan_fetch` builds a single flat array but inserts a sentinel token (e.g. `--talkbox-fetch-boundary--`) between the podman command and the host command. `execute_fetch_plan` splits on the sentinel instead of sniffing for `git fetch`.

**Pros:**
- Preserves the single-flat-array + single-executor shape closest to the current design.
- The boundary is explicit rather than inferred from token adjacency.

**Cons:**
- Introduces a magic token into the plan array that has no meaning to podman or git; it is meaningful only to `execute_fetch_plan`.
- The splitter still exists — it just splits on a sentinel instead of on `git fetch`; the sentinel must be chosen so it can never collide with a real argument.
- Marginally more complex than Option A for no added benefit over it.

### Option C — Split on `podman` boundary like `execute_plan`

Reuse the existing `execute_plan` from [lib/containers.sh](../../../lib/containers.sh), which splits on the `podman` keyword. Since the host-side command is `git fetch` (not `podman`), this would require wrapping the host `git fetch` in a `podman` invocation or reordering so the `podman` keyword delimits commands. This does not fit the host-side `git` command, which must run on the host directly.

**Pros:** reuses the existing executor.

**Cons:** the host-side command is genuinely a `git` command, not a `podman` command; forcing it behind a `podman` boundary is contrived and would change execution venue (the fetch must run on the host). Not viable without distorting the design.

## Recommendation

**Option A (two-array output).** The brittle splitter exists only because `plan_fetch` flattens two unrelated commands into one array. Making the two commands structurally separate from construction removes the splitter — and its failure mode — entirely. The cost is a small signature change to `plan_fetch` and its two callers, which are already unit-tested.

## Selected option

**Option A (two-array output).** Selected by the user. `plan_fetch` populates two caller-declared arrays (the podman bundle command and the host `git fetch` command); the callers run each command array directly. `execute_fetch_plan` is removed entirely.

## Related

- [Issue: `execute_fetch_plan` boundary splitting is brittle](../issues/execute-fetch-plan-brittle-split.gen.md)
- [Review: repository review](../reviews/repository-review.gen.md) (observation: `execute_fetch_plan` is brittle)
