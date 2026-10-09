# Choice: mechanism and placement of the per-container configuration record

*Date: 2026-10-09*

## context

The [common-implementation review](../reviews/container-common-implementation.gen.md) proposes replacing the ~12 container-conditional branch points and 11 dedicated functions with a per-container configuration record with roughly these fields: pasta suffix, nft deny/allow enforcement, write style (bind vs volume), named worktree volume, root image, populate policy, default inheritance chain. In bash there are three plausible representations, and the record must be reachable from [talkbox.sh](../../../talkbox.sh) (write style, deny/allow computation), [lib/containers.sh](../../../lib/containers.sh) (most fields) and [lib/mounts.sh](../../../lib/mounts.sh) (write-volume naming), including from unit tests that source `lib/containers.sh` directly.

## options

### A. Case-based lookup function in a dedicated module (Recommended)

A new `lib/definitions.sh` defining one pure lookup function taking a field name and the container (e.g. `container_config <field> <container>`), implemented as a readable `case` that reads as a table. Sourced by `talkbox.sh` and by `lib/containers.sh`.

- Pros: stateless and pure (no initialisation order concerns, safe under `set -euo pipefail` and in subshells); shellcheck-clean; a single place listing every field per container, which is exactly the "one table" payoff the review identifies; directly unit-testable.
- Cons: string-typed field names are less self-documenting at call sites than named functions; one more module to source.

### B. Associative-array table

A `<container>.<field>`-keyed associative array (or per-container nested maps) populated at source time in a dedicated module.

- Pros: the most table-like representation; field access is a plain lookup.
- Cons: the review itself notes associative arrays are clunkier in bash (quoting, word-splitting of list-valued fields such as the inheritance chain, initialisation before first use, harder linting); list-valued fields need encoding conventions.

### C. Per-field accessor functions

One small function per field (e.g. a pasta-suffix function, an nft-applicability predicate, a default-chain function).

- Pros: the most readable and greppable call sites.
- Cons: ~7 near-identical functions reintroduce the per-field boilerplate the consolidation removes; the "one table" overview is lost (the per-container picture is scattered across function definitions).

## recommendation

Option A: a single case-based lookup in a dedicated `lib/definitions.sh` gives the review's "one table" benefit with the least bash friction, matches the codebase's existing use of `case`-based dispatch (`container_net_suffix`, `inherit_source`), and keeps the record pure and trivially testable.

## decision

**Selected: Option A — case-based lookup function in `lib/definitions.sh`.**
