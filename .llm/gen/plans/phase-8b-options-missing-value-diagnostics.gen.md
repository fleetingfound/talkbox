# Phase 8b: Options requiring a value emit talkbox messages instead of raw bash errors

#flow/redgreen #model/default

## issue

Resolves [options-missing-value-unbound-variable](../issues/options-missing-value-unbound-variable.gen.md).

## specification

Implements the user-facing usage-error behaviour implied by `SPEC.md`/`SPEC.gen.md`'s `talkbox:` diagnostic convention: when `--read`, `--write`, `--port` or `--inherit` is supplied as the final argument with no following value, `talkbox` exits 2 with a message of the form `talkbox: <option> requires a value`, rather than aborting with a raw `$1: unbound variable` diagnostic from `set -u`.

No other aspects of the option grammar change; all currently-valid invocations continue to parse identically.

## external-facing functionality

- `onbox --read` (and `--write`, `--port`, `--inherit` as the final argument) prints `talkbox: --read requires a value` to stderr and exits 2.
- Valid invocations are unchanged.

## files to modify

- [lib/options.sh](../../../lib/options.sh) — in each of the four value-consuming cases (`--read`, `--write`, `--port`, `--inherit`), guard the post-`shift` access to `$1` with an argument-count check and call `die "<option> requires a value" 2` when no value is present. The existing `die` helper in [lib/common.sh](../../../lib/common.sh) already produces the `talkbox:` prefix and exit code.

## files to read during implementation

- [lib/options.sh](../../../lib/options.sh)
- [lib/common.sh](../../../lib/common.sh)
- [test/unit/options.bats](../../../test/unit/options.bats)
- [test/unit/helpers.bash](../../../test/unit/helpers.bash)

## key internal interfaces

No interfaces change. `parse_talkbox_options` continues to populate the same `TALKBOX_*` variables and to signal usage errors via `die <message> <code>` (exit code 2 for usage errors), consistent with the existing `unknown option` path.

## tests

Unit tests in [test/unit/options.bats](../../../test/unit/options.bats), one per affected option, asserting exit status 2 and a `talkbox: <option> requires a value` message when the option is the final argument. No end-to-end test required: the behaviour is fully exercised at the parser layer and the `talkbox:` prefix is already covered by the `unknown option` test.
