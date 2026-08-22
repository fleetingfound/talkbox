# Volume Population Strategy

How read-write volumes for `netbox`/`offbox` (worktree, gitdir, and write mounts) and the root filesystem inheritance are populated from host sources or other volumes, given the `SPEC.md` constraint that any temporary helper container must run without network access and with the host source mounted read-only.

## Option A: Temporary no-network helper container (Recommended)

Use a short-lived `podman run --rm` container with `--network=none` that bind-mounts the host source read-only and writes into the target volume mounted read-write. A small helper script copies the tree preserving ownership/perms (e.g. `cp -a` / `rsync -a`). This satisfies the spec's hard constraint directly.

- Root filesystem inheritance uses `podman commit <source-container> <project-slug>.<container>.root` then runs the new container from that image (no helper container needed).
- Volume-from-volume copies (offbox <- netbox) mount both volumes in the helper container and copy between them.
- Volume-from-host copies mount the host source read-only and the target volume read-write.

**Pros:** fully compliant with the spec's network/isolation requirement; uniform mechanism for all volume initializations; host source never writable by the helper.
**Cons:** helper container startup cost per volume; helper copy script must be shipped (in the image or via `podman run -v` of a host script).

## Option B: `podman volume create` + `podman cp`

Create the volume, then `podman cp` host contents into a temporary mount of the volume.

**Pros:** no helper image/script needed.
**Cons:** `podman cp` into a volume still requires mounting the volume in a container; does not give the read-only-host-source / no-network guarantee required by the spec, and ownership mapping under `keep-id` is harder to control. Likely violates the spec constraint.

## Option C: Populate during target container creation

Mount the host source read-only inside the target container at create time and copy into the volume on first entrypoint run.

**Pros:** no extra container.
**Cons:** couples initialization to the entrypoint; makes `--fresh`/inheritance semantics harder; the target container has network access (onbox/netbox) which violates the no-network intent for host-source copying; offbox's "copy from netbox volume" still needs an extra mechanism.

## Selected

Option A (temporary no-network helper container with read-only host source) - confirmed by user.
