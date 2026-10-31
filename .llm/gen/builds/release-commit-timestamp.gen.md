# Release commit and tag timestamps

## Summary

[.release/release.sh](../../../.release/release.sh) now stamps the main commit created by `git commit-tree` with the author and committer timestamps of the dev commit it is cut from, read via `git show -s --format=%aI/%cI` and passed as `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`. Since `v<version>` is a lightweight tag (a plain ref), its displayed timestamp is the committer date of the commit it points to, so both the main commit and its tag carry the dev commit's timestamp. The script's help text and the [MAP.gen.md](../../../MAP.gen.md) entry were updated to document this.

## Verification

- `shellcheck` and `shfmt -d` pass on the script.
- A scratch-repository release run confirmed the main commit's `%aI`/`%cI` equal the dev commit's (including when the two dates differ on dev), the `v<version>` tag's `%(creatordate)` matches, and `.coreignore` filtering is unchanged.

## Related

- [Phase 29: release automation](phase-29-release-automation.gen.md) — the original release script build, whose behaviour is otherwise unchanged.
