# Phase 20a: shared list-file reading and ordered dedup helpers

Status: SUCCESS

## overview

Implemented [phase-20a-list-file-and-dedup-helpers](../plans/phase-20a-list-file-and-dedup-helpers.gen.md), which resolves the duplication review's production-code items (§1 defaults-file line parsing, §2 ordered dedup loops) with no change to external-facing behaviour.

- [lib/common.sh](../../../lib/common.sh): added `clean_line()` (comment-strip + trim), `read_list_file()` (appends cleaned, non-empty lines of a file to a caller array via nameref; no-op when absent) and the ordered-dedup pair `dedup_ordered()`/`dedup_last_ordered()` (first- and last-occurrence-wins, order-preserving, into an output nameref; the last-wins variant is `dedup_ordered` over the reversed sequence).
- [lib/mounts.sh](../../../lib/mounts.sh): `mount_entries` reads the defaults file through `read_list_file`, cleans CLI specs via `clean_line`, and collapses identical dests last-wins via `dedup_last_ordered` plus a last-source map before the unchanged stable depth sort.
- [lib/network.sh](../../../lib/network.sh): `port_args` and both halves of `deny_allow_args` read their list files through `read_list_file` and dedup via `dedup_ordered`.

Public signatures and emitted arguments are unchanged; a differential run against the pre-refactor code reproduced identical srcs/dsts ordering for duplicate- and depth-heavy inputs (this caught that the old dedup orders collapsed dests by last occurrence, which `dedup_last_ordered` preserves exactly). The pinning coverage demanded by the plan (CLI-spec-over-defaults-file last-wins precedence for read and write dests) already exists in `test/unit/mounts.bats` and was left untouched.

## verification

- `make lint` and `shfmt -d` clean.
- `make test-unit`: 252/252 pass.
- `make test-e2e`: 76/76 pass.

## linked documents

- Plan: [phase-20a-list-file-and-dedup-helpers](../plans/phase-20a-list-file-and-dedup-helpers.gen.md) — scope for the shared list-file reading and ordered dedup helper refactor.
