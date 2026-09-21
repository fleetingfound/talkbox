# Phase 16a: Prune external working containers before `--rm-image`

Test document for [Phase 16a: Prune external working containers before `--rm-image`](.llm/gen/plans/phase-16a-rm-image-prune-external-working-containers.gen.md), which makes `onbox --rm-image`, `netbox --rm-image` and `offbox --rm-image` succeed even when buildah external working containers (created by prior `podman build` calls) reference the base image, while the `image_in_use` guard continues to refuse removal when *real* user-created containers use the image (honouring the SPEC's safety contract at [SPEC.md](SPEC.md) line 253); it resolves the issue [--rm-image blocked by external working containers](.llm/gen/issues/rm-image-blocked-by-external-working-containers.gen.md), in which `podman rmi talkbox/base:latest` fails because external working containers are invisible to the `image_in_use` ancestor filter but are counted by `podman rmi`'s own in-use check.

## New tests

All five new tests are in `test/unit/lifecycle.bats` (the file which already hosts the `plan_rm_image` unit tests at plan L29) and use the podman-shim/log pattern established by `test/unit/containers.bats` and `test/unit/netbox-offbox.bats`. The suite went from 262 pass / 0 fail to 262 pass / 5 fail (`make test-unit`), with exactly the five new tests failing.

### The prune helper (plan L33)

- `prune_external_image_containers queries external containers by ancestor and force-removes each returned ID` — drives the not-yet-existing `prune_external_image_containers talkbox/base:latest` against a shim that returns `ext1`/`ext2` for `podman ps -a --external`, then asserts the shim log contains a `--external --filter ancestor=talkbox/base:latest` query and one `podman rm -f ext1` / `podman rm -f ext2` per returned ID (plan L33: "queries `podman ps -a --external --filter \"ancestor=<image>\" --format '{{.ID}}'` and force-removes each resulting external working container ID via `podman rm -f`"). **Observed red:** the helper is undefined today, so `run` reports exit code 127 (command not found).
- `prune_external_image_containers silently succeeds when no external working containers match` — with a shim returning nothing for the external query, the helper must still exit 0 and issue no `rm` calls (plan L33: "The helper is best-effort: it silently succeeds when no external containers match"). **Observed red:** exit code 127.

### The three `run_*_rm_image` executors (plan L34)

- `run_rm_image prunes external working containers before removing the base image` — runs `run_rm_image "$PROJECT"` against a shim (external query returns `ext1`; `container exists <ctr>` fails so the container-rm branch is skipped) and asserts the external `ps -a --external --filter ancestor=talkbox/base:latest` line and the `rm -f ext1` line both precede the `rmi talkbox/base:latest` line (plan L34: "Each of `run_rm_image`, `run_netbox_rm_image`, and `run_offbox_rm_image` calls the new helper after the `image_in_use` guard passes and before `execute_plan` runs `podman rmi`"). **Observed red:** today the external query is never issued, so the test fails at the `[[ -n "$ext_line" ... ]]` assertion.
- `run_netbox_rm_image prunes external working containers before removing the base image` — identical scenario for `run_netbox_rm_image`. **Observed red:** external query never issued.
- `run_offbox_rm_image prunes external working containers before removing the base image` — identical scenario for `run_offbox_rm_image`. **Observed red:** external query never issued.

## Tests edited

None. No pre-existing test needed modification:

- The existing e2e regression target `netbox --rm-image removes the base image` ([test/e2e/netbox-offbox.bats](test/e2e/netbox-offbox.bats) lines 156–165) is retained unchanged; the plan calls it out as the regression test (plan L44: "the existing `netbox --rm-image removes the base image` test … already captures the desired behaviour and is currently failing. After the fix it should pass. No new e2e test is required"). It passes in the current environment (clean podman 5.4.2 store; `make test-e2e` 76/76) and continues to pass once the prune step is in place.
- The existing unit tests `rm-image plan removes the base image when it is not in use` and `rm-image plan refuses to remove the base image when it is in use` (and the analogous netbox tests) remain valid: the plan leaves `plan_rm_image` and `image_in_use` semantics unchanged (plan L35: "`image_in_use` is **not** modified").

## Tests removed

None. No existing test asserts behaviour inconsistent with the plan: `image_in_use`'s refusal to remove a shared base image while real containers reference it is the SPEC-mandated contract ([SPEC.md](SPEC.md) line 253) and is preserved, and no test pins the (buggy) absence of external-container pruning.

## Coverage notes

- The plan also asks `teardown_talkbox` in `test/e2e/helpers.bash` to gain a best-effort `podman rm -f --external` step (plan L36) so buildah artifacts do not accumulate across suites. This is test-harness hygiene implemented alongside the plan's core change rather than behaviour the new tests must pin, so it has no dedicated failing test here.
- The observed red state is entirely due to the unimplemented helper/wiring: the unit suite fails only the five new tests (exit code 127 for the two direct helper tests, missing-external-query for the three executor tests), and `make test-e2e` remains green (76/76) in the current clean environment.
