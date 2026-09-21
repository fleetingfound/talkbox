# Choice: External working container handling for `--rm-image`

## context

`podman build` (called by `ensure_base_image` in [lib/containers.sh](../../../lib/containers.sh)) creates buildah **external working containers** that persist in podman's container store. These are invisible to `podman ps -a --filter ancestor=` (used by `image_in_use`) but are counted by `podman rmi`'s own in-use check, so `podman rmi talkbox/base:latest` fails with "image is in use by a container" even when `image_in_use` returned false. See [the issue](../issues/rm-image-blocked-by-external-working-containers.gen.md) and [the review](../reviews/rm-image-e2e-failure.gen.md) (mode 2).

`image_in_use` is the SPEC-mandated safety guard ([SPEC.md](../../../SPEC.md) line 253: "will not remove the image if it is being used by other containers"). Its semantics — refuse removal when *real, user-created* containers reference the base image — are correct. External buildah working containers are transient build artifacts, not "containers using the image" in the SPEC's sense.

## options

### Option 1: Prune external working containers before `rmi` (Recommended)

Add a targeted prune step to the `run_*_rm_image` functions (or to `plan_rm_image`) that removes external working containers referencing the base image before emitting `podman rmi`. Concretely, query `podman ps -a --external --filter "ancestor=<base-image>"` and force-remove the resulting IDs.

- Preserves `image_in_use`'s semantics unchanged — the guard continues to protect against real containers.
- After pruning, `image_in_use` and `podman rmi` agree (no external containers remain), so the unforced `podman rmi` succeeds.
- Targeted pruning (filtered by ancestor) avoids removing external containers that belong to unrelated images/projects.
- Also add the same external-container prune to `teardown_talkbox` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) so test runs don't accumulate buildah artifacts across suites.

### Option 2: Make `image_in_use` also detect external containers

Modify `image_in_use` to additionally query `podman ps -a --external --filter "ancestor=<image>"` so the guard's determination matches `podman rmi`'s.

- Semantically wrong: external buildah working containers are transient artifacts, not "containers using the image" in the SPEC's sense. The guard would refuse removal after every `podman build`, making `--rm-image` useless without manual pruning.
- The user would need to manually run `podman rm --force --external` before `--rm-image` could succeed, pushing the problem to the user rather than solving it.

### Option 3: Prune external containers after every `podman build` in `ensure_base_image`

Add a prune step at the end of `ensure_base_image` so external working containers never accumulate.

- Prevents accumulation at the source, benefiting all code paths.
- Does not handle external containers created by other means (manual `podman build`, other tools, prior test suites).
- Adds overhead to every build, even when no `--rm-image` will follow.
- Could be combined with Option 1 for defence-in-depth, but Option 1 alone is sufficient for correctness.

## recommendation

**Option 1.** It directly resolves the `image_in_use` / `podman rmi` mismatch at the point where it matters, preserves the SPEC's safety contract, and is targeted (only prunes external containers referencing the base image). Option 3 can be added later if accumulation becomes a concern in other paths.

## selected

**Option 1: Prune external working containers before `rmi`.** Selected by the user.
