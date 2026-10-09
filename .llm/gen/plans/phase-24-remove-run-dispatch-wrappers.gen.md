# Phase 24: Remove the per-container `run_*` dispatch wrappers

#flow/unified #model/default

## aspects

- No aspect of `SPEC.md` or `SPEC.gen.md` is newly implemented or deferred by this phase. This is a behaviour-preserving simplification of the internal dispatch surface covered by [SPEC.md §implementation](../../../SPEC.md): external behaviour of every `onbox`/`netbox`/`offbox` verb must be unchanged.

## motivation

Test-driven development left behind a family of functions which exist only because tests (and a name-based dispatch scheme) reference them, not because a functional implementation requires them:

1. **The nineteen per-container `run_*` wrappers in [lib/containers.sh](lib/containers.sh)** (`run_onbox`, `run_netbox`, `run_offbox`; the four `*_recontain` variants; the four `*_rebuild` variants; the four `*_rm_container` variants; the four `*_rm_image` variants, where the onbox-named ones forward to the generic-named onbox variants `run_recontain`/`run_rebuild`/`run_rm_container`/`run_rm_image`, which in turn forward to the container-parameterised cores). The container-parameterised cores (`run_container`, `run_recreate`, `run_rm_container_any`, `run_rm_image_any`) already accept the container as their first argument. The wrappers exist only so that `talkbox.sh` can dispatch via the composed name `run_${container}[_<verb>]` and so that unit tests can call `run_netbox` and friends directly.
2. **The `_any` suffix on `run_rm_container_any`/`run_rm_image_any`**, which only disambiguated those cores from the per-container wrapper family; once the wrappers are gone the suffix is a residual artifact.
3. **`list_submodule_git_dirs` in [lib/git.sh](lib/git.sh)**, referenced only by unit tests: the implementation absorbs submodules directly via `git submodule absorbgitdirs` inside `absorb_submodules` and never enumerates the module directories.

## external-facing functionality

Unchanged. Every verb (`-c`/default create, `fetch`, `merge`, `sync`, `--recontain`, `--rebuild`, `--rm-container`, `--rm-image`) for every container produces a byte-identical sequence of `podman` invocations and identical exit statuses, diagnostics and rollback behaviour. The e2e suite and the dispatcher unit tests (which drive `talkbox.sh` as a subprocess over the logging podman shim) pin this and must pass without modification.

## files to create

None.

## files to modify

- [talkbox.sh](talkbox.sh) — in `container_action`, replace the dynamic `"run_${container}_<verb>"` name dispatch with direct calls to the container-parameterised cores, passing the container as the leading argument:
  - the default (create) verb calls the create core with the container name,
  - `recontain`/`rebuild` call the recreate core with the container name and the rebuild flag (after `prepare_git_host`, as today),
  - `rm-container`/`rm-image` call the corresponding removal cores with the container name.
  - Always pass the write srcs/dsts namerefs positionally (they remain empty for `onbox`, since `mount_entries` is only invoked for `netbox`/`offbox`), which removes the conditional `write_entries` padding and lets the onbox special case (currently the `no_mounts` dummy arrays inside the `run_onbox`/`run_recontain`/`run_rebuild` wrappers) disappear from the dispatch entirely.
- [lib/containers.sh](lib/containers.sh) — delete all nineteen `run_*` wrappers listed above; rename `run_rm_container_any` to `run_rm_container` and `run_rm_image_any` to `run_rm_image` (container as first argument, matching the `run_container`/`run_recreate` convention). The cores themselves are otherwise unchanged.
- [lib/git.sh](lib/git.sh) — delete `list_submodule_git_dirs`.
- [test/unit/containers.bats](test/unit/containers.bats) — rewrite the direct `run_onbox`/`run_recontain` call sites to invoke the create/recreate cores with the container name and empty srcs/dsts arrays (declared alongside the existing dummy arrays in the test setup); the assertions are unchanged.
- [test/unit/netbox-offbox.bats](test/unit/netbox-offbox.bats) — rewrite the `run_netbox`/`run_offbox`/`run_netbox_recontain`/`run_offbox_recontain`/`run_netbox_rebuild`/`run_offbox_rebuild` call sites (including the loop driving `run_${c}_${phase}`) to call the cores with the container name and rebuild flag; the assertions are unchanged.
- [test/unit/lifecycle.bats](test/unit/lifecycle.bats) — rewrite the `run_recontain`/`run_rebuild`/`run_rm_container`/`run_rm_image` and per-container `*_rm_container`/`*_rm_image` call sites to the cores with the container name; the assertions are unchanged.
- [test/unit/git.bats](test/unit/git.bats) — remove the two tests covering `list_submodule_git_dirs` (the submodule-absorption behaviour itself remains covered by the e2e and `prepare_git_host` paths).
- [MAP.gen.md](MAP.gen.md) — update the [talkbox.sh](talkbox.sh), [lib/containers.sh](lib/containers.sh) and [lib/git.sh](lib/git.sh) entries to describe the direct core dispatch (dropping the "nineteen `run_*` executor names" and `list_submodule_git_dirs` mentions).

Test names whose descriptions reference the removed wrapper names (e.g. `run_netbox uses the base image…`) may be reworded to name the core plus container, but their assertions must not change.

## files to read during implementation

- [talkbox.sh](talkbox.sh), [lib/containers.sh](lib/containers.sh), [lib/git.sh](lib/git.sh)
- [test/unit/helpers.bash](test/unit/helpers.bash) (shim and `load_container_libs` scaffolding)
- [test/unit/containers.bats](test/unit/containers.bats), [test/unit/netbox-offbox.bats](test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](test/unit/lifecycle.bats), [test/unit/git.bats](test/unit/git.bats), [test/unit/dispatcher.bats](test/unit/dispatcher.bats)
- [SPEC.md](../../../SPEC.md) §implementation and §testing

## key internal interfaces

- The dispatch surface of `container_action` in [talkbox.sh](talkbox.sh): direct calls to `run_container`, `run_recreate`, `run_rm_container` and `run_rm_image` (renamed from the `_any` variants), each taking the container as the leading argument, with the same trailing nameref-array parameters as today.
- The signatures of `run_container`, `run_recreate`, `run_rm_container` and `run_rm_image` are otherwise unchanged; `run_fetch`, `run_merge`, `run_sync` are untouched.
- `list_submodule_git_dirs` is removed with no replacement; `absorb_submodules` continues to call `git submodule absorbgitdirs` directly.

## tests

Unit tests are updated in lockstep with the implementation (hence `#flow/unified`): the call-site rewrites above are mechanical argument reorderings whose assertions are unchanged, and the two `list_submodule_git_dirs` tests in [test/unit/git.bats](test/unit/git.bats) are removed.

- Unit tests: no new tests; every retained test must pass unchanged in its assertions, pinning that the cores produce the same `podman` command sequences per container and verb.
- End-to-end tests: none modified; the existing e2e suite and [test/unit/dispatcher.bats](test/unit/dispatcher.bats) (which exercise `talkbox.sh` externally) serve as the behavioural pin that the dispatch rewrite is externally invisible.

## verification

`make test-unit`, `make test-e2e`, `make lint` and `make format` must all pass; the podman-shim-based unit tests assert exact command lines, so their unchanged assertions demonstrate the byte-identical `podman` behaviour.
