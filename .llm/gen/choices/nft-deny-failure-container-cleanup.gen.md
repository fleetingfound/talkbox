# nft deny install failure — container state on abort

When `install_nft_deny` aborts, the container has already been started (`podman start` + `wait_for_entrypoint` ran successfully) in `run_onbox`/`run_netbox`/`run_netbox_recontain`/`run_netbox_rebuild`. The choice is whether to stop (and optionally remove) the container before raising the error.

## Option A: Stop the container before raising the error (Recommended)

Call `podman stop` (with the standard grace period) on the container before returning a non-zero status, so the user is not left with a running, unenforced container. Do not remove it (the user may want to inspect it).

**Pros:** no orphaned running container with an unenforced deny list; matches the "do not proceed with container orchestration" framing.
**Cons:** adds a stop step on the failure path; the user loses the interactive session they were about to enter.

## Option B: Leave the container running, just return non-zero

Return non-zero without stopping; the caller's existing flow returns early, leaving the container up.

**Pros:** minimal; the user can `podman exec` in to diagnose.
**Cons:** leaves a running container whose deny list is unenforced — exactly the state the fail-hard change is meant to prevent; contradicts "do not proceed with container orchestration."

## Option C: Stop and remove the container

Stop and `podman rm` the container before raising the error.

**Pros:** cleanest host state; no leftover container.
**Cons:** destroys evidence the user might want for diagnosis; removal semantics differ across the four call sites (named volumes, recreate flows).

## Selected

Option A — stop the container (do not remove) before raising the error. Confirmed by user.
