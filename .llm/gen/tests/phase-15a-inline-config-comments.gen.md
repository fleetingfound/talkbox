# Phase 15a: Inline comments in config files

Test document for [Phase 15a: Inline comments in config files](.llm/gen/plans/phase-15a-inline-config-comments.gen.md), which extends the config-file comment rule so a `#` appearing **anywhere** on a line begins a comment (the remainder of the line is ignored), uniformly across `read.mounts`, `write.mounts`, `ports`, `deny.ip` and `allow.ip`, per the confirmed choice [inline-comment-scope](.llm/gen/choices/inline-comment-scope.gen.md) (Option A). This is implemented via a new pure `strip_comment` helper in `lib/common.sh` (plan L46: "prints the input with everything from the first `#` removed. Pure, no side effects, no trimming. Composed with `trim` by callers") which the parse loops of `lib/network.sh` (`port_args`, `deny_allow_args`) and `lib/mounts.sh` (`mount_entries`) then apply as strip-comment-then-trim-then-skip-if-empty (plan L30-32), updating the config-file description in SPEC.md L387.

The implementation was simulated in a scratch copy (`/tmp/opencode/tb-sim`) to validate that every test here passes once the plan is implemented: `make test-unit` 262/262 and `make test-e2e` 76/76 both pass against the simulation, while the current repository shows the intended red state (unit 253 pass / 9 fail).

## New tests

### `test/unit/common.bats` (4, new file)

Direct tests of the plan's key internal interface (plan L46), loading `lib/common.sh`:

- `strip_comment removes everything from the first # onwards` — `'10.0.0.0/8  # Private-Use RFC 1918'` becomes `'10.0.0.0/8  '`. **Observed red:** `strip_comment` is undefined today, so `run` reports exit code 127 (command not found).
- `strip_comment does not trim leading or trailing whitespace` — whitespace around the value survives the strip (the helper is pure and leaves trimming to `trim`, plan L30 "This is a pure string operation (no trimming)"). **Observed red:** exit code 127.
- `strip_comment leaves a string without a # unchanged` — no comment marker means no change. **Observed red:** exit code 127.
- `strip_comment empties a line whose first character is a #` — a full-line comment reduces to the empty string, which the caller's `[[ -z ]]` skip then drops. **Observed red:** exit code 127.

### `test/unit/network.bats` (5)

- `port_args strips an inline comment and keeps the port value` — a `ports` file line `8080  # web server` yields only `-T,8080` (plan L53: "`port_args` strips an inline comment and keeps the port value"). **Observed red:** the current trim-then-`'#'*`-skip loop keeps the whole line, so the output is `-T,8080  # web server` and the exact-shape assertion fails.
- `deny_allow_args strips inline comments from both deny and allow file entries` — `10.0.0.0/8  # Private-Use RFC 1918` in the deny file and `192.168.1.1  # lab host` in the allow file parse to the bare entries, with the allow set still ending `127.0.0.0/8 169.254.1.1/32 ::1` (plan L54). **Observed red:** both sets retain the full commented lines.
- `port_args yields no entry for a line that is only an inline comment` — a file whose only content is `   # only a comment` yields no ports. Guard test (see Coverage notes).
- `deny_allow_args yields no entry for a line that is only an inline comment` — the same comment-only content in both files yields an empty deny set and only the always-allowed allow entries. Guard test (see Coverage notes).

### `test/unit/mounts.bats` (3)

- `mount_entries strips an inline comment from a file line and parses the source spec` — a `read.mounts` line `/a  # a comment` mounts `/a` at `/host/read/a` read-only (plan L57: "`mount_entries` strips an inline comment from a file line and parses the remaining `<source>`/`<source> : <dest>` spec correctly"). **Observed red:** the source path becomes the whole line with the comment, so the derived dest and the `-v` shape are wrong.
- `mount_entries strips an inline comment from a file line and parses the source : dest spec` — `/src : /a/b  # a comment` mounts `/src` at `/a/b`. **Observed red:** the comment corrupts the parsed `<dest>`.
- `mount_entries strips an inline comment from CLI --read and --write specs` — CLI specs `/a  # a comment` passed to both read and write modes parse to `/a` with the default dests `/host/read/a` and `/host/write/a` (plan L58: "`mount_entries` strips an inline comment from a CLI `--read`/`--write` spec", mirroring plan L32 "and from `--read`/`--write` CLI arguments for consistency"). **Observed red:** the comment is retained in the source.

## Tests edited

None. All pre-existing comment/blank-line tests remain valid because the plan's rule is a strict superset of the old one (full-line `#` comments and blank lines are still ignored, plan L22 "Full-line comments and blank lines continue to be ignored as before"):

- `test/unit/network.bats`: `port_args ignores blank and comment lines` and `deny_allow_args ignores blank and comment lines and trims whitespace` — unchanged, and verified to still pass in the simulation.
- `test/unit/mounts.bats`: `mount_args ignores blank lines and comment lines` — unchanged, and verified to still pass in the simulation.
- The e2e suites exercise deny/allow via CLI arguments only, never file contents, and the plan states no end-to-end tests are required for this pure parsing change (plan L60); `make test-e2e` remains green in the simulation.

## Tests removed

None. No existing test asserts behaviour inconsistent with the plan (e.g. no test passes a value containing `#` mid-line, which is the only input whose interpretation changes).

## Coverage notes

- The two guard tests (`port_args yields no entry for a line that is only an inline comment`, `deny_allow_args yields no entry for a line that is only an inline comment`) implement the plan's third network.bats bullet (plan L55: "a line that is only an inline comment (leading `#` after whitespace) still yields no entry (regression of existing behaviour)"). They pin preserved behaviour and therefore pass both before and after implementation — the same guard status as the `TALKBOX_STRICT_NFT=0` tests documented in [Phase 14a](.llm/gen/tests/phase-14a-nft-deny-fail-hard.gen.md) — since both the old trim-then-`'#'*`-skip and the new strip-then-trim-then-skip-if-empty loops drop such lines; they fail if a future rewrite of the parse loops regresses comment-only lines. The same scenario was already exercised by the retained `  # indented` fixtures inside `port_args ignores blank and comment lines` and `deny_allow_args ignores blank and comment lines and trims whitespace`.
- The existing full-line-comment fixtures (`# comment`, `  # indented`) also guard the new pattern's interaction with the old rules: under strip-then-trim, `# comment` first strips to the empty string and `  # indented` strips to whitespace which trim removes, so the skip-if-empty branch is taken exactly as before.
- The mounts CLI-spec regression scenario is exercised through `mount_args` (the file's existing convention), which forwards its CLI arguments to the `mount_entries` CLI loop; mounts.bats has no direct `mount_entries` calls anywhere else in the file.
