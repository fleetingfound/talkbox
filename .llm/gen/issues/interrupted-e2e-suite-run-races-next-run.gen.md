# Interrupted e2e suite run races the immediately following run

Killing a running `make test-e2e` (e.g. the SIGTERM of an interrupted session) does not stop the suite's in-flight nested `systemd-run` units: [test/run-suite.sh](../../../test/run-suite.sh) wraps the whole suite in a `systemd-run` unit with `KillMode=control-group`, but the per-invocation `sdrun` units created by [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) are sibling user units outside that cgroup, so they keep running `podman build`/`start`/`rm` after the parent unit dies. A full suite started immediately afterwards then shows a large fraction of its tests failing fast (~50–100 ms podman failures) while those leftover units still mutate podman storage; one such run recorded 54/77 with 23 failures across every e2e file, and the unchanged suite passed 77/77 on the next clean run. The failure mode is transient and state-dependent rather than a product regression, but it makes a single failing e2e run record untrustworthy right after an interrupted run.

Files causing the issue:

- [test/run-suite.sh](../../../test/run-suite.sh) (the suite-level `systemd-run` wrapper whose `KillMode=control-group` cannot reach the nested units)
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) (`sdrun`, which nests per-invocation `systemd-run` units)

Possible directions: make the suite wrapper stop (or wait for) leftover nested units from a previous interrupted run before starting, or have `sdrun`/teardown tolerate and drain in-flight units; alternatively document a required settling step after any interrupted e2e run before trusting the next run record.
