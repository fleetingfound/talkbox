# Choice: Write-volume discovery for `--rm-container` (revisited)

## context

The earlier choice [rm-container-write-volume-discovery](rm-container-write-volume-discovery.gen.md) selected threading the *current invocation's* parsed write-mount dests into the `rm-container` path. That leaves a residual gap, recorded as the issue [rm-container-write-volumes-need-repeated-write](../issues/rm-container-write-volumes-need-repeated-write.gen.md): write mounts declared when the container was *created* are not recorded anywhere, so `<slug>.<container>.write.<dest-slug>` volumes created then are leaked unless the same `--write` arguments are repeated on the removal invocation.

[SPEC.md](../../../SPEC.md) says `--rm-container` "removes the container, together with associated volumes" — the write volumes created for the container are associated volumes regardless of the removal invocation's arguments.

`plan_container_volumes_rm` in [lib/containers.sh](../../../lib/containers.sh) is shared by `--rm-container` and the `--recontain`/`--rebuild` recreate paths, so the chosen mechanism applies to both (the recreate paths also currently leak write volumes whose dests are absent from the current invocation, and reuse stale volumes when dests are reconfigured).

## options

### Option A: Name-pattern volume listing (Recommended)

At plan time, enumerate the volumes whose names begin with the `<slug>.<container>.write.` prefix (via `podman volume ls` with a name filter) and emit a `podman volume rm -f` token sequence for each match. The worktree and gitdir volumes continue to be removed by name.

- **Pros:** Removes every write volume actually created for the project/container pair, independent of the removal or recreate invocation's arguments; fixes the recreate-path stale-volume leak for free; no dispatch plumbing needed; the listing runs at plan time like the existing `volume_exists` probes.
- **Cons:** Departs from purely name-derived plan output (the plan captures environment-dependent listings); removes volumes from a previous write-mount configuration, which is intentional under the spec's "associated volumes" wording but is a behaviour change for users who reconfigure mounts.

### Option B: Container-mount inspection

Before `podman rm`, inspect the container's `Mounts` and remove the named write volumes it references.

- **Pros:** Removes exactly the volumes the container actually used.
- **Cons:** Requires the container to still exist; introduces a `podman inspect` parsing step into the plan; fails to remove write volumes orphaned by earlier failed removals.

### Option C: Persistent record

Record the write-mount dests on the container (e.g. a `podman label`) at creation time and read the label back at removal.

- **Pros:** Precise; survives invocation changes.
- **Cons:** Most plumbing (label write at every creation path, label read at removal); still misses orphans from containers created before the label existed or from failed creations.

## recommendation

**Option A.** It is the only mechanism which guarantees "no `<slug>.<container>.write.*` volume remains" after `--rm-container` or a recreate, matching the spec's wording, and it removes the invocation-dependence that caused the leak rather than narrowing it.

## selected option

**Option B** (selected by the user). `plan_container_volumes_rm` inspects the container's named-volume mounts before removal and removes every write volume the container actually used, in place of the current-invocation dest-list derivation. Orphaned write volumes left behind by earlier failed removals are out of scope for this choice.
