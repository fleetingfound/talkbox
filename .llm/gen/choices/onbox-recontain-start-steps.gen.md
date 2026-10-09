# Choice: how to resolve the onbox `--recontain` start-time divergence

*Date: 2026-10-09*

## context

[run_recreate](../../../lib/containers.sh) guards its post-`podman start` steps with nested `!= onbox` / `!= offbox` conditions, so `onbox --recontain` and `onbox --rebuild` install no nft deny/allow rules and run no `image/setup.sh`, while the `run_container` path does both for onbox and `SPEC.md` states that for `onbox` and `netbox` "the restrictions are enforced via `nft` before `image/setup.sh` is invoked" and that `image/setup.sh` is invoked after the container has been started (see [the issue](../issues/onbox-recontain-skips-nft-and-setup.gen.md)). The asymmetry must be resolved before the container consolidation so that the consolidated `run_recreate` has a single start-time tail.

## options

### A. Align `run_recreate` with `run_container` (Recommended)

After `podman start`, `run_recreate` applies the same start-time steps as `run_container`: install the nft deny/allow rules for every container except `offbox`, then run `setup.sh` for all containers, then stop. `onbox --recontain`/`--rebuild` become behaviourally identical to `netbox`'s.

- Pros: matches `SPEC.md`'s stated ordering; removes the asymmetry without a special case, leaving one start-time tail for the consolidation; the container is stopped immediately after, so the added work is bounded (two short podman invocations).
- Cons: observable behaviour change for `onbox --recontain`/`--rebuild` (unit tests pinning the skip must be superseded); a recontain of onbox now fails hard when the nft deny set cannot be enforced (as the create path already does).

### B. Formalize the skip as configuration

Keep the skip, but make it an explicit per-container config field (e.g. "run start-time steps on recontain: no for onbox, yes otherwise").

- Pros: no behaviour change; the asymmetry becomes documented data.
- Cons: codifies behaviour that `SPEC.md` neither requires nor describes; the same code path would be configured differently per container for no semantic reason, undermining the consolidation's rationale.

### C. Skip nft and `setup.sh` for all containers on recontain

Make `netbox`/`offbox` match `onbox` by skipping both steps in `run_recreate` entirely.

- Pros: smallest and cheapest recontain path for all containers.
- Cons: changes `netbox`/`offbox` observable behaviour; contradicts `SPEC.md`'s ordering language and the netbox/offbox recontain tests; the nft ruleset would be absent from a recontained netbox until the next invocation.

## recommendation

Option A: it is the only option that both satisfies `SPEC.md` and removes the asymmetry rather than relocating it, and it leaves a single, container-uniform start-time tail for the consolidation phase.

## decision

**Selected: Option A — align `run_recreate` with `run_container`.**
