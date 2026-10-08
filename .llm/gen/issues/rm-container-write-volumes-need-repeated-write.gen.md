# Issue: `--rm-container` leaks write volumes unless `--write` is repeated on the removal invocation

## affected files

- [talkbox.sh](../../../talkbox.sh) — `container_action` dispatch passes only the *current invocation's* `write_dsts` to `run_${container}_rm_container`
- [lib/containers.sh](../../../lib/containers.sh) — `plan_container_volumes_rm` removes write volumes derived from the caller-provided dest list, not from the volumes the container actually uses
- [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) — the `--rm-container` e2e test repeats `--write "$data:/talkbox/wdata"` on the removal command, masking this behaviour

## description

`netbox --rm-container` and `offbox --rm-container` remove the container, its worktree volume, its gitdir volume and its root image, but the `<project-slug>.<container>.write.<dest-slug>` volumes are removed only for write mounts declared on the *removal* invocation (the union of `defaults/write.mounts` and that invocation's `--write` arguments). Write mounts declared when the container was created are not recorded anywhere, so repeating them is the only way they get cleaned up.

Verified empirically (podman 5.4.2):

```sh
netbox --write "$data:/talkbox/wdata" -c --noninteractive true   # creates <slug>.netbox.write.talkbox-wdata
netbox --rm-container                                            # container, worktree and gitdir volumes removed
podman volume ls                                                  # <slug>.netbox.write.talkbox-wdata still present
netbox --rm-container --write "$data:/talkbox/wdata"             # now the write volume is removed too
```

The worktree and gitdir volumes are always removed because their names are derived from the project alone; only the write volumes depend on invocation-specific `--write` arguments.

## spec violation

[SPEC.md](../../../SPEC.md) states: "`onbox --rm-container` removes the `onbox` container, together with associated volumes" (and analogously for `netbox`/`offbox`). The write volumes created for the container are associated volumes regardless of whether their mount spec is repeated on the removal command.

## impact

Orphaned named volumes accumulate on the host after `--rm-container`, consuming disk space and retaining container data (possibly sensitive) after the user believes it has been removed. This is a residual gap of the resolved issue [lifecycle-verbs-leave-named-volumes-orphaned](lifecycle-verbs-leave-named-volumes-orphaned.gen.md): its fix derives the write-volume list from the parsed mount entries of the *current* invocation.

## suggested fix

Before removing the container, enumerate its actual named-volume mounts (e.g. `podman inspect --format '{{range .Mounts}}{{.Name}} {{end}}' <container>`) and remove every `podman volume` whose name matches the `<project-slug>.<container>.write.` prefix, instead of (or in addition to) reconstructing the list from the current invocation's write-mount entries. The existing e2e test should also be tightened to call `--rm-container` *without* repeating `--write` so the leak is caught.
