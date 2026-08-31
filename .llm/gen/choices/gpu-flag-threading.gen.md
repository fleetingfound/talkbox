# Choice: GPU flag threading

#flow/redgreen

## Context

`SPEC.md` (gpu support, lines 347-355) requires that when `--gpu` is passed to `onbox`, `netbox` or `offbox`, the persistent container is created with the extra `podman` options `--device nvidia.com/gpu=all` and `--group-add keep-groups`.

The create argument lists for the three persistent containers are assembled centrally in `plan_onbox`, `plan_netbox` and `plan_offbox` ([lib/containers.sh](../../../lib/containers.sh)). These planners are invoked by the `run_*` executors and by the `plan_*_recontain`/`plan_*_rebuild` planners, so adding the GPU options inside the three planners covers the default-create, recontain and rebuild paths at once.

The open design question is how the parsed `--gpu` flag reaches those planners.

## Option A — explicit `gpu` parameter threaded through every plan/run signature

Add a new `gpu` positional parameter to `plan_onbox`, `plan_netbox`, `plan_offbox`, and thread it through every `run_*`, `run_*_recontain`, `run_*_rebuild`, `create_netbox`, `create_offbox` signature, plus the `onbox_action`/`sandbox_action` call sites in [talkbox.sh](../../../talkbox.sh).

- Mirrors the existing `interactive` parameter.
- Forces every call site to acknowledge the flag (no hidden global dependency).
- Most invasive: touches ~15 function signatures and their call sites.

## Option B — read the `TALKBOX_GPU` global directly inside the planners (Recommended)

Have `parse_talkbox_options` set `TALKBOX_GPU=yes` (default `no`), and have `plan_onbox`/`plan_netbox`/`plan_offbox` append the two GPU options when `TALKBOX_GPU == yes`.

- Matches the established precedent for creation-time-only flags: `create_netbox`/`create_offbox` and the `run_*_recontain`/`run_*_rebuild` executors already read the globals `TALKBOX_FRESH` and `TALKBOX_INHERIT` directly rather than receiving them as parameters.
- GPU is only consumed inside the three planners (which build create args), exactly like `TALKBOX_FRESH`/`TALKBOX_INHERIT` are only consumed inside `inherit_source`. No executor needs to inspect the flag.
- Minimal and targeted: no executor or `talkbox.sh` signature changes beyond the parser.
- Planners are already non-pure (they call `git_mounts_enabled`, `resolve_git_dir`, `volume_exists`), so reading a global does not introduce a new class of impurity.

## Selection

**Option B** — read the `TALKBOX_GPU` global inside the planners. (Selected.)
