# Choice: Handling leftover e2e `sdrun` units from an interrupted suite run

## context

[test/run-suite.sh](../../../test/run-suite.sh) wraps the whole e2e suite in a user `systemd-run` unit with `KillMode=control-group`, but the per-invocation `sdrun` units created by [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) are sibling user units outside that cgroup. When the parent suite unit is killed (e.g. an interrupted session), the nested `sdrun` units keep running `podman build`/`start`/`rm` and mutate podman storage while a subsequently started suite runs, causing a large fraction of its tests to fail fast (~50–100 ms podman failures). The failure mode is transient and state-dependent: the unchanged suite passes on the next clean run.

The nested units currently have system-generated random names and no relationship to the parent suite unit, so nothing stops them when the parent dies.

See the issue document [interrupted-e2e-suite-run-races-next-run](../issues/interrupted-e2e-suite-run-races-next-run.gen.md).

## options

### Option A: Stop-propagation dependency — nested units die with the parent (Recommended)

Give the suite wrapper in `run-suite.sh` a deterministic transient unit name, exported to the suite's environment. Each `sdrun` invocation reads that name and declares `StopPropagatedFrom=` (or `BindsTo=`) on it via `systemd-run --property`, so when the parent suite unit is stopped or deactivates — including by SIGTERM/SIGKILL of its main process or its `RuntimeMaxSec` timeout — systemd stops the nested units and kills their control groups (`sdrun` already sets `KillMode=control-group`). When the environment name is absent (the `timeout(1)` fallback path or direct `bats` runs), `sdrun` behaves exactly as today.

- **Pros:** The nested units are stopped automatically and immediately when the parent dies, so there are no leftovers to race the next run at all; no naming/drain convention to remember; works for both the unit and e2e suites.
- **Cons:** Requires the suite wrapper unit to have a deterministic name and an exported environment variable; stop propagation covers parent deactivation but not the corner case where the parent unit itself keeps running while its client dies (in that case the suite is still running anyway, so a subsequent run racing it is a user error).

### Option B: Preflight stop with named units

Give every `sdrun` invocation a recognizable unit name (a fixed prefix plus a unique suffix, passed via `systemd-run --unit`), and add a preflight step to `test/run-suite.sh` which, before starting the suite, stops every leftover user unit carrying that prefix, printing a note when it does.

- **Pros:** Deterministic — the next run starts from a quiet podman state; works even if the previous parent died without stopping anything at all.
- **Cons:** Reactive rather than preventive: the leftovers mutate podman storage until the next suite starts; adds a naming convention and a preflight step to the harness.

### Option C: Preflight wait

Same unit naming, but the preflight polls until no leftover prefixed units remain active, bounded by a timeout, warning or failing if they do not settle.

- **Pros:** No forcible termination; in-flight operations complete rather than being cut short.
- **Cons:** Delays every clean run start by at least one poll; unbounded leftover work (a long `podman build`) can still exceed the wait; a leftover unit wedged on a hang still blocks the run.

### Option D: Documentation only

No code change; document a required settling step (e.g. a manual `systemctl --user` invocation or a wait) after any interrupted e2e run before trusting the next run record.

- **Pros:** No harness change.
- **Cons:** Relies on human discipline; a single forgotten step produces an untrustworthy run record, which is exactly the reported problem.

## recommendation

**Option A.** It eliminates the leftovers at the source — the nested units are torn down together with the parent suite unit by systemd itself, so the immediately following run starts from a quiet state without any drain convention. Option B can be layered on later as a belt-and-braces preflight if a case emerges where the parent dies without deactivating its unit.

## selected option

**Option A** (selected by the user). The suite wrapper unit gets a deterministic name exported to the suite environment, and each `sdrun` unit declares a stop-propagation dependency (`StopPropagatedFrom=`) on it, so the nested units are stopped together with the parent automatically. No preflight drain step.
