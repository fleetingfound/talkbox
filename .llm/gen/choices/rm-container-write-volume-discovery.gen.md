# Choice: Discovering write volumes for `--rm-container`

## context

The named volumes associated with each container are:

- **onbox**: the gitdir volume `<slug>.onbox.gitdir`.
- **netbox**: the worktree volume `<slug>.netbox.worktree`, the gitdir volume `<slug>.netbox.gitdir`, and one write volume `<slug>.netbox.write.<dest-slug>` per parsed write-mount entry.
- **offbox**: the worktree volume `<slug>.offbox.worktree`, the gitdir volume `<slug>.offbox.gitdir`, and one write volume `<slug>.offbox.write.<dest-slug>` per parsed write-mount entry.

The worktree and gitdir volume names are derivable from the project slug and container alone (via `lib/naming.sh`), so they can be removed without any extra information.

The write volumes, however, are parameterised by `<dest-slug>`, one per write-mount entry. For `--recontain` and `--rebuild`, the dest-slug list is already available because those code paths receive the parsed `_srcs`/`_dsts` arrays (see `plan_netbox_recontain`, `plan_offbox_recontain`, and the `run_*_recontain`/`run_*_rebuild` executors, which are dispatched from `sandbox_action` with `write_srcs`/`write_dsts`).

For `--rm-container`, the dispatch in [talkbox.sh](../../../talkbox.sh) calls `run_${container}_rm_container "$(pwd)"` with **only** the project path — the parsed write mounts are not passed. Therefore the write-volume dest-slug list is not currently available to `plan_netbox_rm_container`/`plan_offbox_rm_container`, and a decision is needed on how those volumes are discovered for removal.

## options

### Option A: Thread write-mount dests into the `rm-container` path (Recommended)

Change the `rm-container` dispatch branch in `sandbox_action` to pass `write_srcs`/`write_dsts` (or just `write_dsts`) through to `run_netbox_rm_container`/`run_offbox_rm_container`, and have those executors forward the dest list to `plan_netbox_rm_container`/`plan_offbox_rm_container`. A new `plan_volume_rm` helper (mirroring `plan_gitdir_volume`'s `volume_exists`-guarded emission) then emits a `podman volume rm -f <name>` token sequence for the worktree, gitdir and each write volume that exists.

- **Pros:** Keeps the pure, static plan model intact — every emitted command is a literal `podman volume rm -f <name>` token sequence that `execute_plan` can split on the `podman` boundary, exactly like the rest of the codebase. Consistent with how `--recontain`/`--rebuild` already obtain the dest list. Deterministic: only the volumes actually configured for this invocation are removed.
- **Cons:** Requires plumbing one extra array parameter through two executors, two plan functions, and the dispatcher's `rm-container` branch, plus updating the existing unit tests for `plan_netbox_rm_container`/`plan_offbox_rm_container` to pass the new parameter.

### Option B: Glob-list volumes by name pattern

Use `podman volume ls --format '{{.Name}}' --filter 'name=<slug>.<container>.write.'` to enumerate matching write volumes at plan time, then emit `podman volume rm -f` for each match. The worktree and gitdir volumes are still removed by name.

- **Pros:** No plumbing of write-mount dests required; `--rm-container` removes every write volume ever created for this project/container, even if the current invocation's write-mount configuration differs from when the container was created.
- **Cons:** Breaks the static plan model: the plan must capture the listed volume names at plan time (so `volume_exists`/listing runs during planning, which it already does for `plan_gitdir_volume`), but the listing is environment-dependent and harder to unit-test deterministically. Removes volumes that may belong to a different write-mount configuration than the current invocation, which could surprise users who reconfigure mounts between invocations.

### Option C: Inspect the container's mounted volumes

Use `podman inspect` on the container to read its `Mounts` and remove the named volumes referenced there.

- **Pros:** Removes exactly the volumes the container actually used, regardless of current mount configuration.
- **Cons:** Requires the container to still exist at removal time (it does, since `podman rm` runs after), but introduces a JSON-parsing step (`podman inspect -f`) into the plan that is awkward to unit-test and diverges from the simple token-sequence plan model. Also fails to remove orphaned write volumes left behind by a previous `--rm-container` that itself failed to remove them.

## recommendation

**Option A.** It preserves the existing pure-plan architecture, is consistent with how `--recontain` and `--rebuild` already obtain the dest-slug list, produces deterministic and unit-testable plan output, and only removes volumes configured for the current invocation — matching the spec's notion of "associated volumes" for the container being removed.

## selected option

**Option A** (selected by the user). The `rm-container` dispatch branch in `sandbox_action` will be updated to pass the parsed `write_srcs`/`write_dsts` arrays through to `run_netbox_rm_container`/`run_offbox_rm_container` and onward to `plan_netbox_rm_container`/`plan_offbox_rm_container`.
