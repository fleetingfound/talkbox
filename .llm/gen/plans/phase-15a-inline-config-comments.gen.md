# Phase 15a: Inline comments in config files

#flow/redgreen #model/default

## specification

Implements the inline-comment portion of `SPEC.md` §implementation (the config-file format described at line 387). Currently SPEC.md states that "blank lines and lines whose first non-whitespace character is #" are ignored in `read.mounts`, `write.mounts`, `ports`, `deny.ip` and `allow.ip`. This phase extends that so that a `#` appearing **anywhere** on a line begins a comment: the remainder of the line (from the first `#` onwards) is ignored, in addition to the existing full-line-comment and blank-line rules.

Per the confirmed choice [inline-comment-scope](../choices/inline-comment-scope.gen.md), this applies uniformly to all five config files.

Deferred: nothing — this is a self-contained parsing change.

## external-facing functionality

Users may now write inline comments in any config file. For example:

```
10.0.0.0/8          # Private-Use RFC 1918
192.168.0.0/16      # Private-Use RFC 1918
```

in `defaults/deny.ip`, and analogously in `defaults/allow.ip`, `defaults/ports`, `defaults/read.mounts` and `defaults/write.mounts`. A `#` may be preceded by any amount of whitespace; everything from the first `#` to end-of-line is discarded before the entry is parsed. Full-line comments and blank lines continue to be ignored as before.

## files to create

None.

## files to modify

- [lib/common.sh](lib/common.sh) — add a `strip_comment` helper that removes everything from the first `#` onwards from a given string. This is a pure string operation (no trimming); callers continue to use the existing `trim` helper afterwards. The two helpers may be composed so that the canonical parse-loop pattern becomes: strip comment, then trim, then skip if empty.
- [lib/network.sh](lib/network.sh) — in `port_args` and `deny_allow_args`, replace the `trim`-then-`'#'*` skip pattern with the strip-comment-then-trim-then-skip-if-empty pattern, so inline comments are stripped from `ports`, `deny.ip` and `allow.ip` entries.
- [lib/mounts.sh](lib/mounts.sh) — in `mount_entries`, apply the same strip-comment-then-trim pattern to both the file-reading loop and the CLI-specs loop, so inline comments are stripped from `read.mounts` and `write.mounts` entries (and from `--read`/`--write` CLI arguments for consistency).
- [SPEC.md](SPEC.md) — update the config-file comment description (line 387) to state that a `#` anywhere on a line begins a comment and the rest of the line is ignored (not only lines whose first non-whitespace character is `#`).

## files to read during implementation

- [lib/common.sh](lib/common.sh) — the `trim` helper to compose with.
- [lib/network.sh](lib/network.sh) — `port_args` and `deny_allow_args` parse loops.
- [lib/mounts.sh](lib/mounts.sh) — `mount_entries` parse loops.
- [test/unit/network.bats](test/unit/network.bats) — existing unit tests for `port_args` and `deny_allow_args` comment handling.
- [test/unit/mounts.bats](test/unit/mounts.bats) — existing unit tests for `mount_entries` (if present).
- [defaults/deny.ip](defaults/deny.ip) — the file that motivates this change; currently uses only full-line comments.

## key internal interfaces

- `strip_comment <string>` in `lib/common.sh`: prints the input with everything from the first `#` removed. Pure, no side effects, no trimming. Composed with `trim` by callers.

## tests

Requires tests, both unit:

- unit tests in `test/unit/network.bats`:
  - `port_args` strips an inline comment and keeps the port value
  - `deny_allow_args` strips inline comments from both deny and allow file entries
  - a line that is only an inline comment (leading `#` after whitespace) still yields no entry (regression of existing behaviour)
- unit tests in `test/unit/mounts.bats` (or the existing mounts unit test file):
  - `mount_entries` strips an inline comment from a file line and parses the remaining `<source>`/`<source> : <dest>` spec correctly
  - `mount_entries` strips an inline comment from a CLI `--read`/`--write` spec

No end-to-end tests are required for this change; it is a pure parsing concern fully covered by unit tests. Existing e2e deny/allow behaviour is unchanged.
