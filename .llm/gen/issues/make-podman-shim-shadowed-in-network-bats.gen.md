# `make_podman_shim` is shadowed by a different implementation in `network.bats`

`test/unit/network.bats:334-363` defines a local `make_podman_shim` that shadows the shared `make_podman_shim` from `test/unit/helpers.bash:13-79` which the file loads first (`load helpers`, line 2). The two functions are incompatible:

- the helpers.bash version takes the shim directory as `$1`, reads behaviour from `PODMAN_*` environment variables and emulates `container/volume/image exists`, `inspect -f` and `ps -a`;
- the network.bats version takes no arguments, prints the shim directory, and reads behaviour from `SHIM_*` environment variables (`SHIM_INSPECT_RC`, `SHIM_NFT_RC`, `SHIM_LOG`, …), emulating only `inspect` and `unshare`.

Which definition is live depends on source order within the file, so a reader (or a future edit that moves the definition or the `load` statement) silently changes which shim the tests use, and improvements to the shared shim never reach `network.bats`. The unit suite passes, so this is a maintainability hazard rather than a functional failure today.

Files causing the issue:

- `test/unit/network.bats` (lines 2, 334-363)
- `test/unit/helpers.bash` (lines 13-79, the shadowed function)

Suggested fix: rename the network.bats-specific function (e.g. `make_nft_shim`), or fold its `SHIM_*` knobs into the shared shim factory as recommended in the [duplication and abstraction review](../reviews/duplication-abstraction-review.gen.md).
