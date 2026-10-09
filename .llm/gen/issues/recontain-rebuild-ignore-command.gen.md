# Issue: `--recontain`/`--rebuild` silently ignore a `-c <command>` argument

## affected files

- [lib/containers.sh](../../../lib/containers.sh) — `run_recreate` never calls `exec_in_container`, so the recreate verbs start and stop the container without ever running the parsed `TALKBOX_COMMAND`
- [talkbox.sh](../../../talkbox.sh) — `container_action` parses `-c`/`--interactive`/`--noninteractive` for every verb and passes `$TALKBOX_COMMAND`/`$TALKBOX_INTERACTIVE` to `run_${container}_recontain`/`run_${container}_rebuild`, which discard them

## description

`netbox --recontain -c --noninteractive '<command>'` and the analogous `--rebuild` invocations recreate and start the container but never execute `<command>`; the argument is accepted and silently dropped. Verified empirically (podman 5.x, minimal image):

```sh
netbox --recontain -c --noninteractive 'echo marker > /tmp/marker'   # container recreated, command not run
netbox -c --noninteractive 'cat /tmp/marker'                          # cat: /tmp/marker: No such file or directory
```

The option parser records the command for every verb (`lib/options.sh` treats `-c` independently of the verb), and the recreate path even threads `$TALKBOX_INTERACTIVE` into `plan_recreate` → `plan_container` (which switches `--interactive`/`--tty` on the created container), so the invocation looks like it is honouring the command while `run_recreate` ends with `stop_container` and no `podman exec`.

## impact

Users combining a lifecycle verb with `-c` get a silently no-op command and may believe the command ran inside the container. The interactive flag is honoured in a misleading way (it affects the created container's allocation but no command is run either way).

## related specification

[SPEC.md](../../../SPEC.md) defines the two behaviours separately (*image and container management*: "`--recontain` recreates the container and all of its associated volumes and then starts the container"; *command execution*: "`onbox -c <command>` runs the provided command within the container") and does not state what their combination should do, so this is a UX/consistency gap rather than a direct spec violation.
