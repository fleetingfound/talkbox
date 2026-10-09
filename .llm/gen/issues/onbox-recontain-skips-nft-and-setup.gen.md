# onbox `--recontain` skips nft deny rule installation and `setup.sh`

*Date: 2026-10-09*

`run_recreate` in `lib/containers.sh` (lines 520-539) guards its start-time steps with:

```bash
if [[ "$container" != onbox ]]; then
	if [[ "$container" != offbox ]]; then
		install_nft_deny_or_die "$ctr" "$6" "$7"
	fi
	run_setup_in_container "$ctr"
fi
```

Consequently, `onbox --recontain` starts the recreated container without installing the nft deny/allow rules and without running `image/setup.sh`, while `netbox --recontain` does both and `offbox --recontain` runs `setup.sh`. This diverges from the `run_container` path (lines 503-518), which installs nft for onbox and netbox and runs `setup.sh` for all containers, and from `SPEC.md`, which states that the deny/allow restrictions for onbox and netbox are "enforced via `nft` before `image/setup.sh` is invoked" and that `image/setup.sh` is invoked after the container has been started.

Practical impact is low: the container is stopped immediately after `podman start` with no command executed inside, and both steps run on the next `onbox` invocation. But the asymmetry between containers in the same code path is hard to justify and is not required by `SPEC.md`.

Files involved:

- `lib/containers.sh` - `run_recreate` (the nested `!= onbox` / `!= offbox` guards)
- `SPEC.md` - network section ("For the `onbox` and `netbox` containers, the restrictions are enforced via `nft` before `image/setup.sh` is invoked") and dotfiles section

Identified during [review of per-container dedication and common-implementation feasibility](../reviews/container-common-implementation.gen.md).
