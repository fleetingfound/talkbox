# Issue: PID 1 (`sleep infinity`) ignores `SIGTERM`, so `podman stop` always waits the full grace period before `SIGKILL`

## Summary

Every `onbox`/`netbox`/`offbox` exit stops the persistent container with
`podman stop -t "$STOP_GRACE_SECONDS" "$ctr"` (`STOP_GRACE_SECONDS=5` in
[lib/containers.sh](../../../lib/containers.sh)). The container's PID 1 is
`sleep infinity`, which installs no signal handler. Linux does **not** apply
the default terminate action to PID 1 for unhandled signals, so the
`SIGTERM` that `podman stop` sends is ignored. Podman therefore blocks for
the entire 5-second grace period on every exit and only then resorts to
`SIGKILL`. The 5 s hang is perceived as the "considerable hang" on exit.

## Evidence

Reproduced against the real `talkbox/base:latest` image with the real
entrypoint and `-t 5`:

```
$ podman run -d --name test-hang2 --entrypoint /usr/local/bin/entrypoint.sh \
    -v entrypoint.sh:/usr/local/bin/entrypoint.sh:ro talkbox/base:latest sleep infinity
$ podman inspect -f '{{.State.Pid}}' test-hang2   # -> host pid
$ cat /proc/<pid>/cmdline   # "sleep infinity "
$ cat /proc/<pid>/comm      # "sleep"
$ time podman stop -t 5 test-hang2
time="..." level=warning msg="StopSignal SIGTERM failed to stop container test-hang2 in 5 seconds, resorting to SIGKILL"
real    0m5.136s
```

PID 1 is `sleep` (the entrypoint's `exec bash -c "$*"` execs `sleep`, since
bash applies its last-command exec optimization to the single-command `-c`
string). `sleep` has no `SIGTERM` handler, and PID 1 ignores unhandled
signals — so `SIGTERM` never terminates the container.

## Cause

- [image/entrypoint.sh](../../../image/entrypoint.sh) ends with
  `exec bash -c "$*"` when arguments are present; the container command is
  `sleep infinity` (see `plan_onbox`/`plan_netbox`/`plan_offbox` in
  [lib/containers.sh](../../../lib/containers.sh)). Bash execs `sleep`,
  making `sleep` PID 1.
- [lib/containers.sh](../../../lib/containers.sh) stops containers with
  `podman stop -t "$STOP_GRACE_SECONDS" "$ctr"` (`STOP_GRACE_SECONDS=5`).
  Because PID 1 ignores `SIGTERM`, the grace period is **always** fully
  consumed (then `SIGKILL`).

## Files involved

- [image/entrypoint.sh](../../../image/entrypoint.sh)
- [lib/containers.sh](../../../lib/containers.sh) (`STOP_GRACE_SECONDS`, the
  `run_*` executors' `podman stop` calls)

## Note on the prior grace-period issue

This supersedes the closed issue
[podman-stop-aggressive-grace](podman-stop-aggressive-grace.gen.md), which
raised `-t 1` to `-t 5` on the assumption that "well-behaved processes exit
immediately on `SIGTERM`". That assumption does not hold here: PID 1 is
`sleep`, which never honors `SIGTERM`, so the grace is **always** exhausted
— increasing the value only lengthens the hang.
