# Issue: `--rm-image` blocked by external working containers

## summary

`podman rmi talkbox/base:latest` (emitted by `plan_rm_image` without `-f`) fails when buildah external working containers — created by every `podman build` call in `ensure_base_image` — reference the image. The `image_in_use` guard does not detect these because `podman ps -a --filter ancestor=` excludes external containers, so the guard passes and the unguarded `podman rmi` fails with a nonzero exit, breaking the `netbox --rm-image removes the base image` e2e test.

## affected files

- [lib/containers.sh](../../../lib/containers.sh) — `plan_rm_image` (lines 148–154) emits `podman rmi` without `-f`; `image_in_use` (lines 204–214) queries `podman ps -a --filter ancestor=` which excludes external containers; `ensure_base_image` (lines 172–176) runs `podman build` which creates the external working containers; `run_netbox_rm_image` (lines 833–844) / `run_onbox_rm_image` (lines 274–285) / `run_offbox_rm_image` (lines 846–857).
- [test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) — `netbox --rm-image removes the base image` (lines 156–165).
- [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — `teardown_talkbox` (lines 51–65) does not remove external working containers.

## reproduction

```bash
podman build -t talkbox/base:latest image/     # creates an external working container
podman rmi talkbox/base:latest                  # fails: "image is in use by a container"
podman ps -a --external --format '{{.ID}}' | xargs podman rm -f
podman rmi talkbox/base:latest                  # now succeeds
```

## analysis

`image_in_use` is the intended safety mechanism per [SPEC.md](../../../SPEC.md) line 253 ("will not remove the image if it is being used by other containers"). It correctly refuses removal when regular containers use the base image. However, external working containers are invisible to `podman ps -a --filter ancestor=`, so `image_in_use` returns false and `plan_rm_image` emits `podman rmi` (without `-f`), which then fails because podman's own removal check includes external containers.

Using `podman rmi -f` would bypass the failure but would also bypass the SPEC's safety contract (force-removing an image that real containers depend on). The correct fix is to either (a) prune external working containers before the `rmi` (e.g. `podman rm --force --external` or `podman container prune --external`), or (b) make `image_in_use` also query `podman ps -a --external --filter ancestor=` so the guard's determination matches `podman rmi`'s.

## related

- [rm-image-e2e-failure review](../reviews/rm-image-e2e-failure.gen.md) — documents this as mode 2 of the recurring e2e failure.
- [Phase 11b teardown-hygiene plan](../plans/phase-11b-e2e-teardown-hygiene.gen.md) — addressed same-slug orphans but not external working containers.
