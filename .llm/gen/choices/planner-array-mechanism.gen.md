# Choice: Planner array-population mechanism

## Context

[Review: Phase 1 onbox implementation as a scaffold](../reviews/phase-1-onbox-scaffold.gen.md) recommendation 1 calls for replacing the line-oriented text protocol between `plan_onbox` (which `printf`s one argument per line) and `run_onbox` (which re-parses lines and special-cases `-v`) with a mechanism that preserves exact argument boundaries. The review suggests two alternatives: a nameref-populating planner, or a `printf '%s\0'` + `mapfile -d ''` pair.

The review's recommendation 6 constrains the design: the planner must continue to consult the filesystem directly for point-in-time existence checks at emit time, and pre-parsed structured inputs (mount lists, port lists) must be passable to the planner as array arguments (not re-read from disk inside the planner).

## Options

### Option A — Nameref-populating planner (Recommended)

The planner takes a caller-declared array name as its first argument and appends to it via `local -n`:

```
plan_onbox <out_array_name> <project> <command> <interactive> [<read_mounts_array> <write_mounts_array> <ports_array>]
```

The executor declares a local array, calls the planner, then runs `podman run "${args[@]}"` with no re-parsing. Unit tests declare a local array, call the planner, and assert on array membership.

**Pros:**
- No subshell / process substitution — the planner is a direct function call, so it can consult caller variables and receive other arrays by nameref (mount/port lists) naturally, satisfying rec 6's "pass as array arguments" requirement.
- No re-parsing whatsoever; argument boundaries are exact by construction.
- Unit tests assert on a real bash array (membership, ordering, count) rather than line-regex — cleaner and more precise.
- The executor becomes a trivial two-liner.

**Cons:**
- Nameref variable-name collision risk: if the caller passes the same name the planner uses internally for its nameref, behaviour is undefined. Mitigated by using an unlikely internal name (e.g. `_plan_out`).
- Requires bash 4.3+ for `local -n` (already required by the `+=` and `${base,,}` usage in `lib/naming.sh`).

### Option B — NUL-delimited stdout + `mapfile -d ''`

The planner emits arguments NUL-delimited to stdout; the executor captures them with `mapfile -d '' -t args`:

```
plan_onbox <project> <command> <interactive>  # printf '%s\0' each arg
```

**Pros:**
- Preserves a stdout-based interface (closer to the current shape); capturing planner output in a subshell is straightforward.
- Argument boundaries are exact (NUL cannot appear in a path on Linux).

**Cons:**
- Still uses process substitution (subshell), so the planner cannot consult caller variables and cannot receive array arguments naturally. Mount/port lists would need to be serialized (e.g. as NUL-delimited positional strings or read from temp files), which is clunky and partially reverses rec 6's "pass structured inputs as array arguments" principle.
- Unit tests must capture stdout via `mapfile` in each test rather than reading a populated array — marginally more ceremony.
- The subshell boundary is the very problem rec 1's third bullet identifies; this option preserves it.

## Recommendation

**Option A (nameref).** It fully eliminates the subshell boundary that rec 1 flags, makes array-argument passing for mount/port lists natural (satisfying rec 6), and yields the cleanest unit-test interface (direct array assertions). The nameref collision risk is trivially mitigated by naming convention.

## Selected option

**Option A (nameref-populating planner).** Confirmed by the user. The planner takes a caller-declared array name as its first argument and appends to it via `local -n`; the executor declares a local array, calls the planner, and runs `podman run "${args[@]}"` with no re-parsing.

## Related

- [Review: Phase 1 onbox implementation as a scaffold](../reviews/phase-1-onbox-scaffold.gen.md) (recommendations 1 and 6)
- [Choice: scaffold-refactor-scope](scaffold-refactor-scope.gen.md)
