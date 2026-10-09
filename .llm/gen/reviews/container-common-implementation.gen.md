# Per-container dedication and the feasibility of a common container implementation

*Date: 2026-10-09*

## Question

1. To what extent do the `onbox`, `netbox` and `offbox` containers rely on dedicated functions in the implementation?
2. To what extent is it feasible to have a common implementation for all three containers, invoked with different configurations, that achieves the behaviour of each container as currently implemented and as required by `SPEC.md`?

## Answer in brief

1. **Very little.** The implementation is already a single container-parameterised pipeline: the container name is threaded as a leading argument from [talkbox.sh](talkbox.sh) through every `run_*`/`plan_*` core in [lib/containers.sh](lib/containers.sh). Only 11 of roughly 120 functions in `lib/` are dedicated to a single container, and all of them are thin (9 symmetric naming one-liners in [lib/naming.sh](lib/naming.sh) and 2 populate planners in [lib/containers.sh](lib/containers.sh)). The remaining per-container behaviour lives in ~12 `case`/`if` branch points inside otherwise-shared functions.
2. **Very feasible — it is ~90% achieved already.** Every remaining branch point varies over data that could be expressed as a small per-container configuration record. The genuinely irreducible differences are the containers' semantics themselves (host-write access, internet access, volume seeding policy), which `SPEC.md` defines per container; a common implementation keeps these as configuration, exactly as the spec's per-container sections describe. One residual asymmetry ([onbox `--recontain` skips `nft` and `setup.sh`](../issues/onbox-recontain-skips-nft-and-setup.gen.md)) is not blocked by, and would be surfaced and resolved by, such a refactor.

## Current state of dedication

### Already fully shared (invoked with `$container` as a parameter)

- **Dispatcher**: [talkbox.sh](talkbox.sh) `container_action` — one code path for option parsing, mount/ports/deny-allow assembly and verb dispatch, with the container as the leading argument; symlink-vs-subcommand invocation is unified at the bottom of the script, as `SPEC.md` requires.
- **Container lifecycle cores**: `run_container`, `run_recreate`, `run_rm_container`, `run_rm_image`, `create_sandbox`, `rollback_creation_and_die`, `execute_plan` in [lib/containers.sh](lib/containers.sh).
- **Planners**: `plan_container` (the single `podman create` argument list for all three, including the `--env TALKBOX_CONTAINER_TYPE=$container` banner switch), `plan_recreate`, `plan_populate_and_create`, `plan_rm_*`.
- **Options** ([lib/options.sh](lib/options.sh)), **mounts parsing** ([lib/mounts.sh](lib/mounts.sh)), **network/nft** ([lib/network.sh](lib/network.sh)), **git transport** ([lib/git.sh](lib/git.sh)) — all container-agnostic, taking the container as a value.
- **In-container side**: one shared [image/Containerfile](image/Containerfile), one [image/setup.sh](image/setup.sh), one [defaults/dotfiles/.bashrc](defaults/dotfiles/.bashrc) keyed on `TALKBOX_CONTAINER_TYPE`.

### Dedicated functions (per container)

All 11 live in two files:

| Function | File | Content |
|---|---|---|
| `onbox_container_name` / `netbox_container_name` / `offbox_container_name` | [lib/naming.sh](lib/naming.sh) | `printf '<slug>.<container>'` one-liners |
| `netbox_worktree_volume` / `offbox_worktree_volume` | [lib/naming.sh](lib/naming.sh) | `printf '<slug>.<container>.worktree'` |
| `netbox_write_volume` / `offbox_write_volume` | [lib/naming.sh](lib/naming.sh) | `printf '<slug>.<container>.write.<dest-slug>'` |
| `netbox_root_image` / `offbox_root_image` | [lib/naming.sh](lib/naming.sh) | `printf '<slug>.<container>.root'` |
| `plan_netbox_populate` | [lib/containers.sh](lib/containers.sh) | seeds worktree + write volumes from the host |
| `plan_offbox_populate` | [lib/containers.sh](lib/containers.sh) | same, but seeds from the corresponding `netbox` volume when it exists (host fallback) |

`onbox` has no worktree/write-volume/root-image helpers because it has no such artifacts (bind mounts, shared base image). `gitdir_volume` is already generic. Only `plan_offbox_populate` contains substantive unique logic (the netbox-volume fallback); `plan_netbox_populate` is the degenerate case of it.

### Container-conditional branch points inside shared functions

| Site | Condition | Effect |
|---|---|---|
| [talkbox.sh](talkbox.sh) `container_action` | `== onbox` / else | write mounts as bind-mount args vs parsed entries + named-volume args |
| [talkbox.sh](talkbox.sh) `container_action` | `!= offbox` | compute deny/allow sets (empty for offbox) |
| [lib/containers.sh](lib/containers.sh) `container_volumes`, `plan_container_volumes_rm` | `!= onbox` | worktree volume in the volume set |
| [lib/containers.sh](lib/containers.sh) `container_net_suffix` | `offbox` vs rest | pasta suffix `-i,lo,-I,talkbox0` vs `--dns-forward,169.254.1.1,--map-guest-addr,none` |
| [lib/containers.sh](lib/containers.sh) `plan_populate_and_create` | `case` netbox/offbox | populate dispatch (onbox: none) |
| [lib/containers.sh](lib/containers.sh) `plan_recreate` | `!= onbox && source != base` | commit source container to root image |
| [lib/containers.sh](lib/containers.sh) `plan_rm_container` | `!= onbox` | remove root image |
| [lib/containers.sh](lib/containers.sh) `inherit_source` | `case` netbox/offbox | default inheritance chain (onbox→base; netbox→onbox; offbox→netbox→onbox) |
| [lib/containers.sh](lib/containers.sh) `resolve_inheritance` | `== onbox` | onbox short-circuits to base |
| [lib/containers.sh](lib/containers.sh) `run_container` | `!= offbox` | install nft deny rules |
| [lib/containers.sh](lib/containers.sh) `run_recreate` | nested `!= onbox` / `!= offbox` | nft + setup skipped for onbox — see [issue](../issues/onbox-recontain-skips-nft-and-setup.gen.md) |
| [lib/mounts.sh](lib/mounts.sh) `mount_volume_args` | `== offbox` vs else | write-volume name prefix |

### Dedicated assets

Only `defaults/art/{onbox,netbox,offbox}.txt` (banner colours) — pure data, already selected at runtime via `TALKBOX_CONTAINER_TYPE`, i.e. already configuration-driven.

### Per-container characterisation

- **onbox**: structurally simplest — host bind mounts for the worktree and writes, base image only, no populate step, no root image, deny/allow enforced via nft, DNS-forwarding pasta mode. Its only dedicated artifacts are its name and its art.
- **netbox**: adds named volumes seeded from the host, root-filesystem inheritance from onbox, deny/allow enforcement.
- **offbox**: adds the netbox-volume seeding fallback, no nft (isolation via `pasta -i,lo,-I,talkbox0` instead), and a two-step default inheritance chain.

## Feasibility of a config-driven common implementation

`SPEC.md` already mandates the common core: one `talkbox.sh` acting as `onbox`/`netbox`/`offbox` via symlink or subcommand (SPEC "implementation"). The question is how much of the residual per-container code can become configuration. The answer: all of it, via a per-container record (e.g. an associative array or a `container_config` lookup) with roughly these fields:

| Field | onbox | netbox | offbox | Replaces |
|---|---|---|---|---|
| name suffix | `onbox` | `netbox` | `offbox` | the 9 naming one-liners + `container_name_of`/`root_image_of`/`worktree_volume_of`/`write_volume_of` dispatchers |
| pasta suffix | DNS-forward | DNS-forward | `-i,lo,-I,talkbox0` | `container_net_suffix` |
| enforce deny/allow | yes | yes | no | the `!= offbox` guards in `container_action`, `run_container`, `run_recreate` |
| write style | bind | volume | volume | the `== onbox` mount branch in `container_action` |
| has root image | no | yes | yes | `plan_recreate`/`plan_rm_container` guards, `resolve_inheritance` short-circuit |
| populate policy | none | host | source-container-volumes-else-host | `plan_netbox_populate`/`plan_offbox_populate` + the `plan_populate_and_create` case |
| default inheritance | base | onbox | netbox, onbox | the `inherit_source` case |

Notes on feasibility:

- **Naming** generalises trivially: every name is `<project-slug>.<container>[.<kind>[.<dest-slug>]]`, so one `container_name <project> <container> [kind...]` helper replaces all nine dedicated functions and four dispatchers.
- **Populate** generalises to "for each volume, copy from the inheritance source's corresponding volume if the source is volume-backed and the volume exists, else from the host". This exactly reproduces `plan_offbox_populate` (source `netbox` → netbox volumes with host fallback; source `onbox`/`base` → host, since onbox has no volumes) and `plan_netbox_populate` (always host). One caveat: `SPEC.md` pins netbox to *always* seed from the host ("The read-write volumes of `onbox` and `netbox` are always copied from the host"), so under an explicit `--inherit offbox` the netbox policy must stay `host` rather than follow the source — i.e. the populate policy is a property of the target container, not derivable from the source alone. A one-field config captures this; a fully general "seed from source" rule would not.
- **Network** is a single config field (the pasta suffix) plus the nft flag; `pasta_net`, `port_args`, `deny_allow_args` and the nft machinery are already shared and need no change.
- **Inheritance** reduces to a default-chain list per container plus the existing shared `--fresh`/`--inherit` override logic, which is already container-agnostic.
- **The recontain path** is where commonisation has the most to clarify: the nested `!= onbox` / `!= offbox` conditions implement (for onbox only) a skip of both nft and `setup.sh`, diverging from the `run_container` path and from the netbox/offbox recontain behaviour — see the linked issue. A config-driven `run_recreate` would either apply the same start-time steps as `run_container` for all containers (resolving the asymmetry) or make the skip an explicit, justified config field.

### Limits and costs

- The three containers' *semantics* cannot be merged away — direct host writes, internet access, and volume isolation are the product definition, and `SPEC.md` specifies them per container. A common implementation makes these configuration, which is precisely what the spec's structure supports (its per-container sections differ only in these data points).
- `onbox` is the degenerate case (no populate, no root image, no write volumes). A unified pipeline must carry `if`-free degenerate config (empty populate list, optional root image), which adds a little indirection but no behavioural risk; the current dispatch already effectively does this with `case` arms.
- In bash, a config table (associative arrays keyed by container) is somewhat clunkier than the existing `case` statements; readability is a legitimate counterargument for keeping 2–3 of the branch points as explicit `case`s (notably `inherit_source`, whose chain reads clearly as written).
- The test suites already pin per-container behaviour externally (`test/unit/dispatcher.bats` pins per-container verb execution, write-volume naming and pasta port threading; `test/e2e/onbox.bats` and `test/e2e/netbox-offbox.bats` cover container behaviour end-to-end), so a config-driven refactor is well protected against regression.
- Benefit beyond tidiness: adding a hypothetical fourth container (e.g. a second isolated tier) would become a config entry plus `SPEC.md` text, instead of edits across 6 branch sites.

## Effect on codebase length

The consolidation is roughly length-neutral, with a modest net reduction. The core shell codebase is 1,558 lines (`talkbox.sh` + `lib/` + `image/setup.sh`). The consolidation-affected code, measured directly, is:

| Affected code | Lines (incl. braces, excl. blanks) |
|---|---|
| 9 dedicated naming one-liners in `lib/naming.sh` | ~27 |
| 4 naming dispatchers (`container_name_of`, `root_image_of`, `worktree_volume_of`, `write_volume_of`) | ~30 |
| `plan_netbox_populate` + `plan_offbox_populate` | ~39 |
| `container_net_suffix` case | ~7 |
| `inherit_source` default-chain case | ~18 |
| remaining per-container guards (`talkbox.sh`, `run_container`, `run_recreate`, `plan_recreate`, `plan_rm_container`, `container_volumes`, `plan_container_volumes_rm`, `plan_populate_and_create`, `mount_volume_args`) | ~25 |

That is ~145 lines of per-container code. A config-driven implementation replaces it with a configuration table plus lookup helpers (~40-60 lines, given bash's wordiness for associative arrays and field accessors), one generic naming helper (~6 lines replacing the 27 + 30 above), one unified populate planner (~22 lines replacing 39), and collapsed branch sites (call-site guards become config lookups of comparable length, so roughly a wash there; the `inherit_source` case shrinks to ~4 lines).

The expected net change is therefore between about −60 and +20 lines — within ±4% of the codebase, most likely a small reduction. The unaffected bulk (`lib/git.sh` at 253 lines, `lib/network.sh` at 141, `lib/options.sh` at 106, `lib/mounts.sh` at 132, `lib/common.sh`, `lib/merge.sh`, `image/setup.sh`) is already container-agnostic and untouched. So the consolidation's payoff is not fewer lines but fewer places to touch per container; the codebase length stays essentially the same while the per-container branch count drops from ~12 scattered sites to one table.

## Conclusion

The three containers rely on dedicated functions only to a marginal extent — 11 thin functions out of ~120, of which only `plan_offbox_populate` contains non-trivial unique logic — and the architecture is already the common, container-parameterised implementation that `SPEC.md` prescribes. Completing the commonisation so that the three containers are pure configuration (a ~7-field record replacing 11 functions, 4 dispatchers and ~12 branch points) is straightforwardly feasible with no change in observable behaviour, with the single substantive decision being the recontain-path asymmetry noted in the issue below.

## Related

- [Issue: onbox `--recontain` skips nft deny rules installation and `setup.sh`](../issues/onbox-recontain-skips-nft-and-setup.gen.md)
