# Build: Phase 21 — onbox create/recontain ensure the base image exists

Status: SUCCESS

Implements [Phase 21](../plans/phase-21-onbox-base-image-probe.gen.md), resolving the [onbox base-image regression](../issues/onbox-base-image-no-longer-probed.gen.md) introduced by Phase 20e, where the dispatcher's dropped `ensure_base_image` calls left `talkbox.sh onbox` (default verb) and `onbox --recontain` failing with a raw registry-pull error when the shared base image was missing.

- [lib/containers.sh](../../../lib/containers.sh) — `resolve_inheritance` no longer short-circuits past the probe on the onbox arm: the onbox/base short-circuit and the `inherit_source_for` resolution now share a single trailing guard, so `ensure_base_image` fires for every container whose resolved inheritance source is `base` (including `onbox`) whenever the caller's rebuild flag is not `yes`. Explicit rebuild paths still plan their build in `plan_recreate` and never probe; non-base (commit) inheritance still probes nothing.

The red tests were committed ahead of this build in the [test pass](../tests/phase-21-onbox-base-image-probe.gen.md): the two superseded executor pins (zero `image exists` on the onbox create/recontain paths) now assert the probe, two new unit tests cover the build-when-missing create and recontain paths, and a new e2e test removes `talkbox/base-e2e:latest` and asserts `onbox -c --noninteractive true` auto-builds it.

`make test-unit` (305/305) and `make test-e2e` (77/77) pass, including the zero-probe rebuild pins (`run_rebuild`, `run_netbox_rebuild`, `run_offbox_rebuild`), the netbox/offbox base-fallback probe tests and the dispatcher `onbox --rm-container` pin; `make lint` and `make format` are clean. The [MAP.gen.md](../../../MAP.gen.md) `lib/containers.sh` entry already described the corrected probe scope and needed no update. The issue is marked resolved in the issues index, and the plan is marked complete in the plans index. No dispute or verdict documents were involved, and no new issues were discovered.
