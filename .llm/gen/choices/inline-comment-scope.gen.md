# Inline-comment scope

#choice

The user requested inline comments (a `#` that may appear after content, with the rest of the line ignored) in `defaults/deny.ip` and `defaults/allow.ip`.

`SPEC.md` line 387 describes the comment/blank-line behaviour for **all** config files collectively (`read.mounts`, `write.mounts`, `ports`, `deny.ip`, `allow.ip`), and the same `trim`-then-`#`* skip pattern is duplicated across `port_args` and `deny_allow_args` in `lib/network.sh` and `mount_entries` in `lib/mounts.sh`.

## Option A: Inline comments in all config files (Recommended)

Apply inline-comment stripping uniformly to `read.mounts`, `write.mounts`, `ports`, `deny.ip` and `allow.ip`, by introducing a shared `strip_comment` helper in `lib/common.sh` and using it in every config-file parse loop.

- Pros: single consistent rule, matches the way SPEC.md already groups these files; lets users annotate any config file the same way; the shared helper removes the duplicated trim-then-comment logic.
- Cons: a `#` inside a mount source/dest *path* would be treated as a comment start. In practice no one mounts paths containing `#`, and the spec already treats a leading `#` as a comment in these files.

## Option B: Inline comments only in `deny.ip` and `allow.ip`

Apply inline-comment stripping only inside `deny_allow_args`, leaving `port_args` and `mount_entries` unchanged.

- Pros: minimal surface; no risk to mount path parsing.
- Cons: inconsistent behaviour across config files that SPEC.md groups together; users annotating `ports` or `*.mounts` inline would silently get malformed entries.

## Selected

Option A — apply inline-comment stripping uniformly to all config files.

**User-confirmed:** All config files (Recommended).
