# Issue: `execute_fetch_plan` boundary splitting is brittle

## Affected files

- [lib/git.sh](../../../lib/git.sh) — `execute_fetch_plan` and its callers `run_fetch` / `run_merge`
- [test/unit/git-transport.bats](../../../test/unit/git-transport.bats) — the `execute_fetch_plan splits the plan at the git fetch boundary` test

## Description

[lib/git.sh](../../../lib/git.sh) `execute_fetch_plan` splits the fetch plan into two commands by detecting the token `git` immediately followed by `fetch` in the plan array. This works only because the podman command's internal `git bundle create` has `git` followed by `bundle`, not `fetch`.

The splitter is therefore coupled to the incidental shape of the plan rather than to an explicit structure. If the plan ever gains an additional `git fetch` token sequence (for example a future in-container fetch step), the splitter could misbehave — splitting at the wrong boundary and producing malformed commands.

`plan_fetch` builds a single flat array containing two logically distinct commands (a no-network `podman run` that bundles the gitdir volume, and a host-side `git fetch`), and `execute_fetch_plan`'s only job is to split that array at the boundary between them and run each in turn. The implicit `git fetch` detection is a fragile way to find that boundary.

## Suggested fix

Replace the implicit boundary detection with an explicit structure. See the associated choice document for the design options (two-array output, explicit delimiter token, etc.).

## Related

- [Review: repository review](../reviews/repository-review.gen.md) (observation: `execute_fetch_plan` is brittle)
- [Review: git transport review](../reviews/git-transport-review.gen.md) (§`execute_fetch_plan` reuse)
- [Choice: execute_fetch_plan boundary mechanism](../choices/execute-fetch-plan-boundary.gen.md)
