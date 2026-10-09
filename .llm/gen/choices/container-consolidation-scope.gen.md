# Choice: scope of the container-implementation consolidation

*Date: 2026-10-09*

## context

The [common-implementation review](../reviews/container-common-implementation.gen.md) identifies ~12 container-conditional branch points in otherwise-shared functions and 11 dedicated functions (9 naming one-liners, 2 populate planners), and proposes a ~7-field per-container configuration record replacing them all. The review also concedes that in bash a config table is somewhat clunkier than `case` statements and that readability is a legitimate argument for keeping 2–3 branch points explicit (notably `inherit_source`, whose default chains read clearly as written).

## options

### A. Full config-driven consolidation (Recommended)

Every branch point becomes a config lookup: pasta suffix, nft applicability, write style, named worktree volume, root image, populate policy and the default inheritance chains (as an ordered parent list per container). The 9 naming one-liners and the 2 populate planners are removed, and the remaining `case`/`if` sites collapse behind config lookups.

- Pros: per-container knowledge lives in exactly one table; adding a container becomes a config entry plus `SPEC.md` text instead of edits across ~6 branch sites; the review's stated goal — "modified only via distinct container-specific configurations" — is met without exceptions.
- Cons: the `inherit_source` chains become an indirect list-walk instead of a readable `case`; slightly more indirection at a few call sites.

### B. Config for data-like fields, retained cases for the rest

Convert the data-like fields (pasta suffix, nft applicability, write style, volumes, root image, populate policy) to config, but retain 2–3 explicit branch points as `case` statements — notably the `inherit_source` default chains, and possibly the populate dispatch in `plan_populate_and_create`.

- Pros: keeps the most readable branches readable; slightly less indirection.
- Cons: per-container knowledge remains in code, so the consolidation is incomplete: a new container still requires editing retained `case` sites; the boundary between "config" and "code" knowledge becomes arbitrary.

## recommendation

Option A: the divergence between the three containers is exactly the data the review tabulates, and the user-facing goal is a common implementation modified *only* by configuration. The inheritance chains are data (ordered parent lists) and read fine as a table row walked by the existing shared `--fresh`/`--inherit` logic.

## decision

**Selected: Option A — full config-driven consolidation.**
