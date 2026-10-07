# Phase 22c: unit scaffolding consolidation and data-driven test folds

#flow/pin #model/default

## scope

Resolves the remaining items of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md): §13 (per-file unit-test scaffolding) and §16 (container-fold repetition and the line-number extraction idiom).

- Implemented in [test/unit/helpers.bash](../../../test/unit/helpers.bash):
  - a shared `load_container_libs` helper replacing the identical `load_onbox_plan`/`load_netbox_plan`/`load_lifecycle_plan` indirections (which exist only because `load_lib` cannot be called at file scope);
  - the shared `use_podman_shim` (standard shim activation: shim on `PATH`, exported `PODMAN_LOG` and `PODMAN_IMAGES` seeded from `base_image_name`), the shared `plan_subcommands`, and the `array_contains`/`array_has_none` pair, replacing the per-file copies in [containers.bats](../../../test/unit/containers.bats), [netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) and [lifecycle.bats](../../../test/unit/lifecycle.bats); the dispatcher variant in [dispatcher.bats](../../../test/unit/dispatcher.bats) (which drives `talkbox.sh` as a subprocess and cannot source `lib/naming.sh`) either joins the shared helper with an explicit image argument or stays local with a comment explaining why;
  - a generic `log_line_no <pattern> <file>` line-number helper (the `grep -n … | head -n 1 | cut -d: -f1` idiom, ~30 occurrences), with the existing `podman_line_no` kept as the `PODMAN_LOG` specialisation; an equivalent helper lands in [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) for the local-log sites in [git-identity.bats](../../../test/e2e/git-identity.bats).
- Data-driven folds (container-parameterised repetition collapsed into loops, following the established `git-transport.bats` pattern; a test family is foldable when its per-container differences are mechanically derivable from the container name, per the guardrails below):
  - the three "rm_image prunes external containers" tests in [lifecycle.bats](../../../test/unit/lifecycle.bats) (onbox/netbox/offbox) become one test looping over the three containers;
  - the recontain/rebuild ordering tests in [netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) stop duplicating their assertion block internally (recontain, log truncation, rebuild);
  - the six same-shape tests in [git-identity.bats](../../../test/e2e/git-identity.bats) fold into container-parameterised tests;
  - the onbox/netbox `--deny-ip blocks a denied address…` enforcement pair in [deny-allow.bats](../../../test/e2e/deny-allow.bats) folds into one container-loop test (the IPv6 variant and the nft-installer test stay separate — their skip guards and behaviour differ substantively).
- Deliberately not folded: families whose per-container differences are substantive — different assertions, preconditions, skip guards or expected behaviour — or whose fold would require per-container conditionals inside the loop body, since bats tests are deliberately explicit.

No aspect of `SPEC.md` changes. No production file is touched; external-facing behaviour is unchanged.

## files to be created

None. Modified: [test/unit/helpers.bash](../../../test/unit/helpers.bash), [test/e2e/helpers.bash](../../../test/e2e/helpers.bash), [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats), [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats), [test/e2e/git-identity.bats](../../../test/e2e/git-identity.bats), [test/e2e/deny-allow.bats](../../../test/e2e/deny-allow.bats). No `MAP.gen.md` update: `test/` is excluded from core files by `.coreignore`.

## relevant files to be read

- [test/unit/helpers.bash](../../../test/unit/helpers.bash) (the target home for the shared scaffolding, including its existing `load_lib` and line-assertion helpers)
- [test/unit/containers.bats](../../../test/unit/containers.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats](../../../test/unit/lifecycle.bats) (the scaffolding copies and the fold sites), [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats) (its `use_podman_shim` variant)
- [test/e2e/git-identity.bats](../../../test/e2e/git-identity.bats) (the six-test fold and the local-log line-number sites)
- [test/e2e/git-transport.bats](../../../test/e2e/git-transport.bats) (the established `for c in …` container-fold pattern to follow)

## key internal interfaces

- `load_container_libs` in [test/unit/helpers.bash](../../../test/unit/helpers.bash): loads `naming.sh`, `mounts.sh`, `network.sh` and `containers.sh` in dependency order, replacing the three per-file loaders; call sites keep their local alias names or call the shared helper directly.
- Shared `use_podman_shim`, `plan_subcommands`, `array_contains`/`array_has_none` in [test/unit/helpers.bash](../../../test/unit/helpers.bash): identical bodies to the current per-file copies; the per-file definitions are deleted.
- `log_line_no <pattern> <file>` in both helpers files: prints the 1-based line number of the first matching line, empty when absent; `podman_line_no` remains the `PODMAN_LOG` specialisation.

## consolidation guardrails

- Folds are limited to tests whose per-container differences are mechanically derivable from the container name — container names, executor dispatch, naming helpers, volume and image names — and expressible in the loop body without per-container conditionals. A fold that would need an `if` per container is the signal to keep the tests separate; likewise, tests differing in assertions, preconditions, skip guards or expected behaviour stay apart.
- The fold deliberately trades failure isolation within a folded test (a netbox failure masks the offbox iteration until it is fixed). This is acceptable only because the folded families verify the same behaviour per container, coverage is unchanged, and the container loop is the established in-repo convention (`git-transport.bats`); if finer isolation is ever needed, the folded tests can be re-split per container.
- The failing container must remain identifiable from the bats output of a folded test (the loop body's `run` output and assertion context carry it); assertions and command sequences stay spelled out in the test body — only the container dimension is looped, and only scaffolding (loaders, shim activation, line-number extraction) is shared.

## tests

Test-infrastructure restructuring plus test-body folds; no new product behaviour. The existing unit and e2e assertions are the safety net and must hold: each folded test must retain exactly its current coverage (same invocations, same assertions) across all loop iterations — the fold is mechanical, not a coverage change.

Tests superseded and removed by the folds (they are replaced by container-parameterised equivalents with identical coverage):

- the three `run_rm_image prunes external working containers before removing the base image` tests in [lifecycle.bats](../../../test/unit/lifecycle.bats) (the onbox/netbox/offbox variants) become one test looping over the three containers;
- the `run_netbox`/`run_offbox recontain and rebuild` ordering pair in [netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) folds into one container-parameterised test whose body contains the shared assertion block once per phase (recontain, log truncation, rebuild) instead of duplicated per container;
- the six same-shape tests in [git-identity.bats](../../../test/e2e/git-identity.bats) (two assertions × three containers) fold into container-parameterised tests;
- the onbox/netbox `--deny-ip blocks a denied address while a non-denied address remains reachable` pair in [deny-allow.bats](../../../test/e2e/deny-allow.bats) folds into one container-loop test.

No other tests are superseded; the deleted `load_*_plan`/`use_podman_shim`/`plan_subcommands`/`array_contains`/`array_has_none` definitions and the replaced line-number idioms are scaffolding, not tests. `make lint` and `make format` must remain clean over all modified files. The full `make test-unit` and `make test-e2e` suites must pass at the end of the phase.
