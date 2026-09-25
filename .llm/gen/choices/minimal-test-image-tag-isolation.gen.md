# Choice: Isolating the test base image from the production `talkbox/base:latest` tag

## context

The e2e suite currently builds the production [image/Containerfile](../../../image/Containerfile) as the shared image `talkbox/base:latest` (see `ensure_base_image_e2e` in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash)). The production Containerfile installs editors (`neovim`, `less`), terminal tools (`tmux`, `fzf`, `tree`), runtimes (`node`, `uv`/python 3.12) and coding agents (`claude-code`, `opencode`, `pi-coding-agent`, `aider-chat`) — a multi-minute, network-heavy build that no e2e test actually needs: the only in-container binaries the suite exercises are bash, git (including `git-upload-pack`), curl and coreutils.

Switching the tests to a minimal Containerfile creates a tag problem: the base image tag is the hardcoded literal returned by `base_image_name()` in [lib/naming.sh](../../../lib/naming.sh) (`talkbox/base:latest`), and every base-image consumer flows through that one function — the create/rebuild planners, `ensure_base_image`, the `netbox`/`offbox` root-image inheritance fallback, the `fetch`/`sync` temporary containers in [lib/containers.sh](../../../lib/containers.sh) and [lib/git.sh](../../../lib/git.sh), and the `--rm-image` lifecycle verb. If tests keep building their minimal image under the shared production tag, then:

- a pre-existing user image short-circuits `ensure_base_image_e2e` (tests silently run the heavy image, defeating the purpose), and
- test builds (including the e2e `--rebuild` tests, which build unconditionally) steal or replace the user's production `talkbox/base:latest` tag — the user's real `onbox` sessions would then silently run the minimal image.

So the test suite needs a way to target a distinct image tag (e.g. `talkbox/base-e2e:latest`) that reaches every `base_image_name()` consumer inside the code under test.

## options

### Option 1: env-var override honoured by `base_image_name()` (Recommended)

`base_image_name()` returns the value of `TALKBOX_BASE_IMAGE` when set, defaulting to `talkbox/base:latest` otherwise. The e2e helpers define the dedicated test tag once and forward it through `sdrun` (which already forwards `PATH` via `systemd-run -E`), so every talkbox invocation under test sees it: helper-driven runs, inline `sdrun bash -c` invocations (e.g. the symlink and GPU-shim tests) and `expect`-driven interactive tests (children of the forwarded environment). Direct podman references in tests (`deny-allow.bats`'s `podman run`, `netbox-offbox.bats`'s `podman image exists`, the `ancestor=` prune filter in `ensure_base_image_e2e`) switch to the same tag constant.

- Single point of change; every base-image consumer (planners, inheritance fallback, fetch/sync temp containers, `--rm-image`) follows the override automatically.
- Default production behaviour is completely unchanged; the override is opt-in.
- Precedent exists: the implementation already honours `TALKBOX_ROOT` and `TALKBOX_STRICT_NFT` environment hooks.
- Hermetic: the user's production image tag is never touched by tests, and tests never silently run the user's image.
- Adds a small undocumented env-var hook to the implementation (mitigated by existing `TALKBOX_*` precedent).

### Option 2: keep the shared production tag

Build the minimal Containerfile under `talkbox/base:latest` unchanged.

- No implementation change at all.
- Test builds steal/retag the user's production image; a user's pre-existing image silently disables the minimal build; the e2e `--rebuild` tests replace the user's `talkbox/base:latest` with the minimal image, breaking their real sessions.
- Whichever image was built first silently wins for both tests and production use.

### Option 3: rewrite the tag in the copied `lib/naming.sh`

`mk_talkbox` already copies `lib/` into a per-test temp directory; a `sed` there could replace the hardcoded literal with the test tag.

- No production implementation change; distinct tag.
- Tests no longer exercise the production code verbatim — the code under test is mutated per-run.
- Brittle: any rename or refactor of `base_image_name()`/the literal silently breaks the rewrite and reintroduces the tag collision.

## recommendation

**Option 1.** It is the only approach that is both hermetic (no interaction with the user's production image in either direction) and faithful (the code under test runs verbatim). The one-line override in `base_image_name()` follows the established `TALKBOX_*` env-hook pattern, and `sdrun` forwarding covers every invocation path used by the suite, including `expect` interactive tests.

## selected

**Option 1 (user-selected): env-var override honoured by `base_image_name()`.**

`base_image_name()` in [lib/naming.sh](../../../lib/naming.sh) returns `${TALKBOX_BASE_IMAGE:-talkbox/base:latest}`. The e2e helpers define a dedicated test tag (e.g. `talkbox/base-e2e:latest`) and `sdrun` forwards it as `TALKBOX_BASE_IMAGE` into every systemd-run unit alongside `PATH`, so all talkbox invocations under test (helper-driven, inline `bash -c`, `expect`-driven) and all direct podman references use the test tag. Default production behaviour is unchanged.
