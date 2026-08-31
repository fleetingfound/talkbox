# Tests: Phase 8b options requiring a value emit talkbox messages instead of raw bash errors

Linked plan: [phase-8b-options-missing-value-diagnostics.gen.md](../plans/phase-8b-options-missing-value-diagnostics.gen.md)

Summary: this phase makes the value-consuming options `--read`, `--write`, `--port` and `--inherit`, when supplied as the final argument with no following value, exit 2 with a `talkbox: <option> requires a value` message instead of aborting with a raw `$1: unbound variable` diagnostic from `set -u` — resolving [options-missing-value-unbound-variable.gen.md](../issues/options-missing-value-unbound-variable.gen.md) and implementing the `talkbox:` diagnostic convention implied by `SPEC.md`.

## New tests

- `test/unit/options.bats` — `--read as the final argument requires a value and exits 2`: `run parse_talkbox_options --read` and assert `status -eq 2` and `output` containing `talkbox: --read requires a value`, per the plan's "`onbox --read` (and `--write`, `--port`, `--inherit` as the final argument) prints `talkbox: --read requires a value` to stderr and exits 2" and its tests section ("one per affected option, asserting exit status 2 and a `talkbox: <option> requires a value` message when the option is the final argument").
- `test/unit/options.bats` — `--write as the final argument requires a value and exits 2`: same assertions for `--write`, expecting `talkbox: --write requires a value`.
- `test/unit/options.bats` — `--port as the final argument requires a value and exits 2`: same assertions for `--port`, expecting `talkbox: --port requires a value`.
- `test/unit/options.bats` — `--inherit as the final argument requires a value and exits 2`: same assertions for `--inherit`, expecting `talkbox: --inherit requires a value`.

The tests run at the parser layer only, matching the plan's "No end-to-end test required: the behaviour is fully exercised at the parser layer and the `talkbox:` prefix is already covered by the `unknown option` test." They mirror the existing `unknown options are rejected with exit code 2 and a message` test, which already establishes the `run parse_talkbox_options <args>` + `status -eq 2` + `talkbox:` message pattern.

## Tests edited

- None. The plan changes no existing behaviour for valid invocations ("No other aspects of the option grammar change; all currently-valid invocations continue to parse identically"), so no existing test assertion needed updating.

## Tests removed

- None. No pre-existing test is inconsistent with the plan: every existing `test/unit/options.bats` test supplies a value for the value-consuming options (e.g. `--read '/a:/b'`, `--inherit offbox`) or exercises a flag that takes no value, and none asserts the current broken `$1: unbound variable` diagnostic that the plan removes.
