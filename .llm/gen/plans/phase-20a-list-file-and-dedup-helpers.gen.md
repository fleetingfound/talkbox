# Phase 20a: shared list-file reading and ordered dedup helpers

#flow/refactor #model/default

## scope

Resolves duplication items §1 and §2 (defaults-file line parsing loop; ordered dedup loops) of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md), production code only.

- Implemented: internal refactor of the parsing/dedup plumbing behind `mount_entries` in [lib/mounts.sh](../../../lib/mounts.sh) and `port_args`/`deny_allow_args` in [lib/network.sh](../../../lib/network.sh).
- Deferred: the test-harness duplication items (§10–§16) are out of scope for this resolution; all other review items are handled in separate Phase 20 plans.

No aspect of `SPEC.md` changes. This refactors the implementation of the mount-file/ports/deny-allow parsing rules (SPEC.md "mount files", "mount specification format", "network", and the blank-line/comment rules under "implementation"). All external-facing functionality (emitted podman arguments, error behaviour, ordering) is unchanged.

## files to be created

None. Modified: [lib/common.sh](../../../lib/common.sh), [lib/mounts.sh](../../../lib/mounts.sh), [lib/network.sh](../../../lib/network.sh). Update the [MAP.gen.md](../../../MAP.gen.md) descriptions of the modified files.

## relevant files to be read

- [lib/common.sh](../../../lib/common.sh), [lib/mounts.sh](../../../lib/mounts.sh), [lib/network.sh](../../../lib/network.sh)
- [test/unit/mounts.bats](../../../test/unit/mounts.bats), [test/unit/network.bats](../../../test/unit/network.bats) (behaviour-pinning tests)

## key internal interfaces

- New `read_list_file` helper in [lib/common.sh](../../../lib/common.sh): appends cleaned lines (comment-stripped, trimmed, empty-skipped) from a file to a caller-declared array via a nameref, silently doing nothing when the file is absent. Replaces the five hand-written loops in `mount_entries` (defaults file), `port_args`, and the deny/allow halves of `deny_allow_args`.
- The CLI-spec cleaning in `mount_entries` reuses the same strip/trim pair through a small shared cleaning helper instead of re-spelling it.
- New `dedup_ordered` helper in [lib/common.sh](../../../lib/common.sh): first-occurrence-wins, order-preserving deduplication of elements into an output nameref. Used by `port_args` and both dedup loops of `deny_allow_args`. The last-source-wins variant needed by `mount_entries` (CLI specs override defaults-file entries with identical dests) is expressed via the same helper or a documented sibling, preserving current semantics exactly.

The public signatures and outputs of `mount_entries`, `mount_args`, `mount_volume_args`, `port_args` and `deny_allow_args` are unchanged.

## tests

Unit tests required. The existing tests in [test/unit/mounts.bats](../../../test/unit/mounts.bats) and [test/unit/network.bats](../../../test/unit/network.bats) pin the file-parsing, precedence and dedup behaviour (including the last-wins mount precedence test) and must keep passing unchanged. The pinning pass should add any missing behaviour-level coverage, in particular the CLI-spec-over-defaults-file last-wins precedence for identical write dests if not already covered. Unit tests for the new helpers themselves may be added alongside the refactor. No existing tests are superseded or removed — no tested internal interface is dropped.
