# Review: Recurring `netbox --rm-image` e2e failure

## scope

This review examines the single failing test in the latest recorded e2e run, `.llm/gen/runs/test-e2e.gen.yaml` (`total=76 pass=75 fail=1`, started 2026-09-11T15:47:22Z), and determines why the failure persists despite the [Phase 11b teardown-hygiene fix](../plans/phase-11b-e2e-teardown-hygiene.gen.md). It supersedes the environmental-only diagnosis in [failing-tests-review](failing-tests-review.gen.md), which predates the current run.

## current run state

| suite | total | pass | fail | exit |
|-------|-------|------|------|------|
| test-unit | 262 | 262 | 0 | 0 |
| test-e2e | 76 | 75 | 1 | 1 |
| test-canary | 2 | 0 | 2 | 1 |
| test-timeout | 1 | 0 | 1 | 1 |

- The unit suite now passes fully (262/262). The `resolve_branches` test defect documented in [failing-tests-review](failing-tests-review.gen.md) was resolved by [Phase 8d](../plans/phase-8d-git-transport-test-default-branch.gen.md).
- The canary and timeout suites fail by design — they assert intentionally false conditions and a non-terminating command to verify the harness reports failures and enforces timeouts. These are expected failures, not defects.

The only genuine failure is:

```
test/e2e/netbox-offbox.bats :: netbox --rm-image removes the base image
```

## the failing test

[test/e2e/netbox-offbox.bats](../../../test/e2e/netbox-offbox.bats) lines 156–165:

```bash
@test "netbox --rm-image removes the base image" {
    run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'true'
    [[ "$status" -eq 0 ]]
    run sdrun podman image exists talkbox/base:latest
    [[ "$status" -eq 0 ]]
    run run_talkbox "$PROJECT" "$TALKBOX" netbox --rm-image
    [[ "$status" -eq 0 ]]          # <-- fails here
    run sdrun podman image exists talkbox/base:latest
    [[ "$status" -ne 0 ]]
}
```

## two failure modes

Reproduction reveals two distinct conditions under which `netbox --rm-image` exits nonzero. Both produce the same test assertion failure but through different code paths.

### mode 1 — orphan containers trigger the `image_in_use` guard (the recorded run)

`run_netbox_rm_image` ([lib/containers.sh](../../../lib/containers.sh) lines 833–844) calls `image_in_use` (lines 204–214) before removing the base image. `image_in_use` runs `podman ps -a --filter ancestor=talkbox/base:latest` and returns true if **any** container other than the current project's netbox container matches:

```bash
image_in_use() {
    local image="$1" ctr="$2"
    local names name
    names="$(podman ps -a --filter "ancestor=$image" --format '{{.Names}}')"
    for name in $names; do
        if [[ "$name" != "$ctr" ]]; then
            return 0
        fi
    done
    return 1
}
```

Because `talkbox/base:latest` is [shared across all projects](../../../SPEC.md) (line 260), containers left behind by **other** e2e test suites (different project slugs) match the ancestor filter. `image_in_use` returns true, `run_netbox_rm_image` dies:

```
talkbox: cannot remove base image: it is in use by other containers
```

This is the failure mode captured in the recorded run. The fact that only test 12 fails (tests 13–14 pass) confirms mode 1: the `image_in_use` guard fires *before* `podman rmi`, so the base image is **not** removed and subsequent tests that call `ensure_base_image` still find it present.

At the time of investigation, three orphan containers from the `talkbox-security-test` suites were present:

```
talkbox-security-test.netbox
talkbox-security-test2.onbox
talkbox-security-test2.netbox
```

The [Phase 11b](../plans/phase-11b-e2e-teardown-hygiene.gen.md) `teardown_talkbox` ([test/e2e/helpers.bash](../../../test/e2e/helpers.bash) lines 51–65) only removes containers whose names match the **current** `$PROJECT_SLUG` (`$slug.onbox`, `$slug.netbox`, `$slug.offbox`). It does not touch containers from other slugs. Cross-suite orphans therefore survive teardown and trigger mode 1 in whichever suite runs the `--rm-image` test last.

### mode 2 — external working containers block `podman rmi` (newly identified)

After removing the cross-slug orphans, the test still fails — but through a different path. `image_in_use` passes (no regular containers match the ancestor filter), so `run_netbox_rm_image` proceeds to `execute_plan`, which runs `podman rmi talkbox/base:latest` (emitted by `plan_rm_image`, [lib/containers.sh](../../../lib/containers.sh) lines 148–154, **without** `-f`). This `podman rmi` fails:

```
Error: image used by 3cd35062696e8f4169e57db583ded71ba01ed8690251ece12a8a4f918fb2b532:
image is in use by a container: consider listing external containers and force-removing image
```

The `3cd35062696e…` ID is an **external working container** — a buildah artifact created by `podman build`. These accumulate in podman's container store every time `ensure_base_image` ([lib/containers.sh](../../../lib/containers.sh) lines 172–176) runs `podman build -t talkbox/base:latest`. They are visible via `podman ps -a --external` but are **not** returned by `podman ps -a --filter ancestor=`, so `image_in_use` does not see them.

Verification: after removing all external working containers (`podman ps -a --external --format '{{.ID}}' | xargs podman rm -f`), `podman rmi talkbox/base:latest` succeeds cleanly (exit 0), and the `--rm-image` test passes.

This mode is the more fundamental problem: even in a perfectly clean environment with no cross-slug orphans, repeated `podman build` calls (from `--rebuild`, from `ensure_base_image` rebuilding after prior `--rm-image` tests, or from prior e2e suites) seed external working containers that eventually block `podman rmi`. See the linked issue [rm-image-blocked-by-external-working-containers](../issues/rm-image-blocked-by-external-working-containers.gen.md).

## why Phase 11b did not resolve this

[Phase 11b](../plans/phase-11b-e2e-teardown-hygiene.gen.md) consolidated per-test cleanup into `teardown_talkbox <slug>`, which removed same-slug containers, root images, and volumes. This addressed within-suite orphans from interrupted runs but left two gaps:

1. **Cross-slug orphans** (mode 1): `teardown_talkbox` is scoped to the current slug. Containers created by other e2e suites (e.g. `talkbox-security-test.*`) are never cleaned and survive as ancestors of the shared base image.
2. **External working containers** (mode 2): `teardown_talkbox` does not remove buildah working containers, which are invisible to `podman ps -a` (without `--external`) and accumulate from every `podman build` call.

## verdict

- The `netbox --rm-image removes the base image` failure is **not** purely environmental and does **not** disappear in a clean environment — it recurs whenever external working containers exist, which is the normal state after any prior `podman build`.
- The recorded run's failure is mode 1 (cross-slug orphan containers trigger `image_in_use`), but mode 2 (external working containers block `podman rmi`) is the deeper, more reliable trigger.
- `image_in_use`'s refusal to remove a shared base image while other containers use it is correct per [SPEC.md](../../../SPEC.md) line 253. The defects are in test hygiene (cross-slug cleanup) and in `plan_rm_image`/`ensure_base_image` not accounting for external working containers.
