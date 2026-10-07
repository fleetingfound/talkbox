# E2e setup/teardown parameterisation mechanism

How the per-file `setup()`/`teardown()` boilerplate repeated across the seven e2e bats files (review §10) is parameterised, and how `volume_mountpoint`/`container_stopped` (review §11) are shared.

Every e2e file repeats the `mk_project` → `mk_talkbox` → `ensure_base_image_e2e` → slug/ctr derivation sequence in `setup()` and the kill-server → `teardown_talkbox` → `rm -rf` sequence in `teardown()`, with per-file variance in which ctr variables are derived, whether a host-server PID is tracked, which extra directories are removed, and per-file PATH/git setup.

## Options

### A. Shared pair plus registration helpers (Recommended)

A shared `e2e_setup`/`e2e_teardown` pair in `test/e2e/helpers.bash` performs the standard sequence and sets the standard variables. Per-file `setup()`/`teardown()` remain as thin wrappers that call the shared pair and add their file-specific state. Cleanup of extra directories and host-server PIDs goes through small registration helpers callable both from `teardown()` and mid-test (the deny-allow/lifecycle pattern of killing the server inside the test and clearing the registration).

- Pros: the cleanup contract becomes uniform and discoverable in one place; per-file variance stays explicit at its site of use; mid-test registration clearing keeps working.
- Cons: each file still carries two small wrapper functions.

### B. Fully declarative shared pair

Selected: **A. Shared pair plus registration helpers.**

The shared pair reads per-file scope variables (e.g. a list of extra directories, which ctr variables to derive) declared at file scope, with no per-file wrappers.

- Pros: most compact; a new e2e file only declares its differences.
- Cons: hides control flow behind variable conventions; awkward for mid-test PID cleanup and per-file one-off setup steps (PATH exports, initial commits); harder to follow in bats, where explicitness is the suite convention.

### C. Shared helpers only

Keep the per-file setup/teardown blocks; only move `volume_mountpoint`/`container_stopped` into `test/e2e/helpers.bash`.

- Pros: no structural change.
- Cons: leaves ~100 lines of duplicated lifecycle/cleanup contract in place; a new e2e file must still re-copy it correctly.
