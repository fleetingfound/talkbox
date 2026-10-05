# Choice: mechanism for eliminating the write-mount double parse in `sandbox_action` (review §9)

## context

In [talkbox.sh](../../../talkbox.sh), `sandbox_action` calls `mount_entries` to compute `write_srcs`/`write_dsts` (needed by the `run_*` executors) and then calls `mount_volume_args`, which internally re-runs `mount_entries` on the same defaults file and CLI specs ([lib/mounts.sh](../../../lib/mounts.sh)). The write mounts are parsed twice per invocation. `mount_volume_args` is only called from `sandbox_action` in production code; it is unit-tested directly in [test/unit/mounts.bats](../../../test/unit/mounts.bats) (four tests) and used at two call sites in [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats).

## options

### A. Change `mount_volume_args` to accept precomputed entries (Recommended)

Change `mount_volume_args` to take the already-parsed write srcs/dsts arrays (namerefs, as `mount_entries` produces) instead of the file/project/home/CLI-spec parameters, since `sandbox_action` always has those arrays in hand. The existing `mount_volume_args` unit tests are superseded: they are rewritten to build the srcs/dsts arrays first (via `mount_entries` or literals) and then assert the same emitted `-v` volume tokens.

- Pros: single parse per invocation; no new production surface; the function's contract ("volume args from write entries") becomes explicit.
- Cons: four unit tests in `test/unit/mounts.bats` and two call sites in `test/unit/netbox-offbox.bats` must be updated (superseded tests, identified in the Phase 20e plan).

### B. Add a from-entries variant, keep `mount_volume_args` as-is

Keep the current `mount_volume_args` signature and add a second entry point that derives volume args from precomputed srcs/dsts arrays; `sandbox_action` switches to the new variant.

- Pros: existing tests untouched.
- Cons: the file+CLI-spec form becomes production-dead code kept alive only by its tests — a new instance of exactly the duplication this review is resolving.

### C. Leave the double parse in place

- Pros: zero churn; the parse is cheap and both calls go through the same `mount_entries`, so there is no drift risk.
- Cons: leaves a redundant full re-parse of the write-mount file and CLI specs on every sandbox invocation.

## recommendation

Option A: it removes the double parse without adding a parallel production surface, and the required test updates are small and mechanical.

## decision

**Selected: Option A — `mount_volume_args` accepts precomputed write srcs/dsts arrays.** The four `mount_volume_args` tests in `test/unit/mounts.bats` and the two call sites in `test/unit/netbox-offbox.bats` are superseded and rewritten against the new signature.
