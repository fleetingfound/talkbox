# Build: Phase 17a — ASCII art banner on container startup

Status: **SUCCESS**

Implemented [Phase 17a](.llm/gen/plans/phase-17a-ascii-art-banner.gen.md): interactive `onbox`, `netbox` and `offbox` shells now display distinct coloured ASCII art before the first prompt, rendered by [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) from files bind-mounted read-only at `/talkbox/art/` by the three persistent-container planners, per the design choices [ASCII art display location](../choices/ascii-art-display-location.gen.md) (Option B) and [ASCII art file format and storage](../choices/ascii-art-file-format.gen.md) (Option A).

## Overview

- `defaults/art/onbox.txt`, `defaults/art/netbox.txt`, `defaults/art/offbox.txt` - the three existing repo art assets (Rebel-font container names) now carry ANSI SGR colour sequences in `\033` octal notation (blue `\033[0;34m` for `onbox`, cyan `\033[0;36m` for `netbox`, red `\033[0;31m` for `offbox`) and end with a `\033[0m` reset so no colour state leaks into the shell.
- [lib/containers.sh](../../../lib/containers.sh) - `plan_onbox`, `plan_netbox` and `plan_offbox` each add the conditional read-only bind-mount `$TALKBOX_ROOT/defaults/art:/talkbox/art:ro` (guarded on directory existence, like the `defaults/dotfiles` mount, and independent of `git_mounts_enabled`), so the default-create, recontain and rebuild paths all inherit the mount.
- [defaults/dotfiles/.bashrc](../../../defaults/dotfiles/.bashrc) - a banner block before the `PS1` assignment skips when the exported sentinel `_TALKBOX_BANNER_SHOWN` is set, when `TALKBOX_CONTAINER_TYPE` is empty, or when `/talkbox/art/${TALKBOX_CONTAINER_TYPE}.txt` is absent (no-op outside a talkbox container); otherwise it passes the art file content through `printf '%b'` (interpreting `\033` into raw ESC bytes), emits a trailing newline, and exports the sentinel so subshells do not repeat the art.
- [MAP.gen.md](../../../MAP.gen.md) - added entries for the three art files and `defaults/dotfiles/.bashrc`, and noted the art bind-mount in the `lib/containers.sh` description.

Per the plan, no changes were made to [image/setup.sh](../../../image/setup.sh), [image/Containerfile](../../../image/Containerfile), [lib/options.sh](../../../lib/options.sh), [talkbox.sh](../../../talkbox.sh) or [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) (`mk_talkbox` already copies `defaults/` recursively, so the art is available in e2e without a helper change). The temporary no-network helper containers never source `.bashrc`, so no art mount is needed there.

## Test edits

No tests were edited. The existing suite remains aligned: the planner unit tests assert individual arguments (not full lists) so the new mount is transparent, and the `.bashrc` unit test sources the file on the host where `/talkbox/art` does not exist, exercising the graceful-degradation no-op path while its `PS1` assertions still hold. The interactive e2e tests drive sessions via `expect` with marker matching, so the banner output does not disturb them.

## Verification

- `make test-unit` - exit `0`; 277/277 tests passed.
- `make test-e2e` - exit `0`; 76/76 tests passed, including the interactive-shell tests.
- Manual verification: an interactive `onbox` session via `expect` displays the blue ONBOX art followed by the `\033[0m` reset and the prompt; the three container types render their distinct colour codes; a child shell inheriting `_TALKBOX_BANNER_SHOWN=1` skips the banner; sourcing without `TALKBOX_CONTAINER_TYPE` or with a missing art file is a no-op.
