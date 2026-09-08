# Phase 13a: Remove dead `_deny` nameref parameter from plan functions

Test document for [Phase 13a: Remove dead `_deny` nameref parameter from plan functions](.llm/gen/plans/phase-13a-remove-dead-deny-nameref.gen.md), a behaviour-preserving maintainability refactor (per the [dead `_deny` nameref issue](.llm/gen/issues/dead-deny-nameref-in-plan-functions.gen.md)) which drops the never-read deny-array parameter from the six plan functions `plan_recontain`, `plan_rebuild`, `plan_netbox_recontain`, `plan_offbox_recontain`, `plan_netbox_rebuild` and `plan_offbox_rebuild` (the deny set continues to be enforced only by the `run_*` executors via `install_nft_deny` after `podman start`).

## New tests

None — the plan's test section requires no new tests ("No new tests are required. No end-to-end tests are affected"), because no externally observable behaviour changes: the e2e suite exercises the `run_*` executors, whose signatures and behaviour are unchanged.

## Tests edited

The plan requires the unit-test call sites of the six plan functions to be brought in line with the cleaned signatures (no trailing deny argument) and to *pass against the existing pre-refactor implementation*, which the current conditional blocks already tolerate: `plan_recontain`/`plan_rebuild` declare `_deny` only inside `if (($# > 6))`, and the netbox/offbox variants only enter their deny block when `$# > 9`, so with the deny argument removed the `local source="$9"` initialisation reads the source value directly and the deny block is skipped. None of the edits fail against the current implementation — they are green both before and after the refactor, which is exactly the behaviour-preservation confirmation the plan asks for.

- `test/unit/containers.bats` — the `DENY` trailing positional argument is removed from the eight `plan_recontain`/`plan_rebuild` invocations (7 tests: "onbox recontain plan passes the GPU options to podman create when TALKBOX_GPU is yes", "onbox rebuild plan passes the GPU options to podman create when TALKBOX_GPU is yes", "onbox recontain plan propagates --init to podman create", "onbox rebuild plan propagates --init to podman create", "onbox recontain and rebuild plans propagate the prompt host env vars to podman create", "onbox recontain plan propagates the /run/talkbox tmpfs to podman create", "onbox rebuild plan propagates the /run/talkbox tmpfs to podman create"), so the call sites pass exactly six arguments (`args project interactive read write ports`). The now-unused `DENY=()` fixture in `setup()` is removed.
- `test/unit/netbox-offbox.bats` — the `DENY` positional argument (passed before `base`, i.e. in the position the deny nameref currently occupies) is removed from the twelve `plan_netbox_recontain`/`plan_offbox_recontain`/`plan_netbox_rebuild`/`plan_offbox_rebuild` invocations (10 tests covering `--init` propagation, the prompt-host env vars, and the `/run/talkbox` tmpfs propagation for the netbox/offbox recontain and rebuild plans), so the call sites pass exactly nine arguments with `base`/the source at position 9. The now-unused `DENY=()` fixture in `setup()` is removed.
- `test/unit/lifecycle.bats` — confirmed consistent, no edit needed: its plan-function tests already omit the deny argument (e.g. `plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS` and `plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS onbox`) and pass unchanged, further demonstrating the absent-argument tolerance of the current implementation.

## Tests removed

None — no test is removed; every edited test remains and passes (`make test-unit`: 242/242, `make test-e2e`: 73/73).
