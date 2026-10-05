# Duplication and reusable-abstraction review

Review of the talkbox codebase for duplicated code and missing reusable abstractions, covering `talkbox.sh`, `lib/*.sh`, `image/setup.sh` and the test harness under `test/`. This document is standalone: file paths and line ranges refer to the repository at the time of review.

## Summary

| # | Duplication | Copies | Location(s) | Suggested abstraction |
|---|---|---|---|---|
| 1 | Defaults-file line parsing loop (strip comment → trim → skip empty) | 5 | `lib/mounts.sh`, `lib/network.sh` | `read_list_file` helper in `lib/common.sh` |
| 2 | Ordered dedup loop over `local -A seen` | 4 | `lib/network.sh` ×3, `lib/mounts.sh` ×1 | `dedup_ordered` helper |
| 3 | Slug normalisation body (lowercase/hyphenate/collapse/trim) | 3 | `lib/naming.sh` ×2, `test/e2e/helpers.bash` ×1 | `slugify` helper |
| 4 | Per-container resource naming + `*_of` dispatch layer | ~16 fns | `lib/naming.sh`, `lib/containers.sh` | parametric `resource_name` |
| 5 | `onbox_action` vs `sandbox_action` skeletons | 2 | `talkbox.sh` | one container-parameterised action |
| 6 | Source-resolution + populate/create tails | 2 | `lib/containers.sh` (`create_sandbox` vs `plan_recreate`) | shared resolution helper |
| 7 | Bundle tmp-dir lifecycle + `plan_fetch` execution | 2 | `lib/git.sh` (`run_fetch` vs `run_merge`) | shared `bundle_fetch` helper |
| 8 | No-network `podman run` prefix; git-mount quadruple | 3 + 2 | `lib/git.sh`, `lib/containers.sh` | `plan_no_net_run`, git-mount helper |
| 9 | e2e `setup()`/`teardown()` boilerplate | 7 | `test/e2e/*.bats` | parameterised helpers in `test/e2e/helpers.bash` |
| 10 | `volume_mountpoint`/`container_stopped` helpers | 2 files | `test/e2e/git-transport.bats`, `merge-sync.bats` | move to `test/e2e/helpers.bash` |
| 11 | Inline podman-shim heredocs | ~14 | unit + e2e bats files | parameterised shim factory |
| 12 | Per-file `load_*_plan`/`setup`/`use_podman_shim`/`plan_subcommands` | 3 files | `test/unit/{containers,netbox-offbox,lifecycle}.bats` | move to `test/unit/helpers.bash` |
| 13 | HTTP-server readiness poll loop | 4 | `test/e2e/deny-allow.bats` ×3, `lifecycle.bats` ×1 | `wait_for_http` helper |
| 14 | `sdrun bash -c 'cd "$1" && …'` wrapper idiom | ~15 | `test/e2e/*.bats` | extend `run_talkbox` |
| 15 | Container-fold repetition (onbox/netbox/offbox; recontain/rebuild) | many | unit + e2e bats files | data-driven loops |
| 16 | `grep -n … | head -n 1 | cut -d: -f1` line-number idiom | ~40 | unit + e2e bats files | `log_line_no` helper |

Overall the production `lib/` layer is in good shape — it has clearly already been through a consolidation pass (see [containers-sh-consolidation-review](containers-sh-consolidation-review.gen.md)) — and the remaining duplication there is mostly small, local and mechanical. The dominant duplication burden sits in the test harness, which has grown organically and now re-derives shims, fixtures and setup blocks per file.

## Production code

### 1. Defaults-file line parsing loop (5 copies)

The loop

```bash
while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(strip_comment "$line")"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    <append>
done <"$file"
```

appears in:

- `lib/mounts.sh:59-67` (`mount_entries`, defaults file)
- `lib/mounts.sh:69-77` (`mount_entries`, CLI specs — same strip/trim/skip on each spec)
- `lib/network.sh:14-21` (`port_args`)
- `lib/network.sh:40-47` (`deny_allow_args`, deny file)
- `lib/network.sh:49-56` (`deny_allow_args`, allow file)

A `read_list_file <file> <nameref_out>` helper in `lib/common.sh` that appends cleaned lines to an array would collapse all five sites to one line each. The CLI-spec cleaning in `mount_entries` could reuse the same strip/trim pair via a tiny `clean_spec` function.

### 2. Ordered dedup loops (4 copies)

The "first occurrence wins, order preserved" dedup over an associative array appears in `port_args` (`lib/network.sh:23-31`), twice in `deny_allow_args` (`lib/network.sh:59-75`), and in a reverse-iteration variant in `mount_entries` (`lib/mounts.sh:78-87`). The reverse-iteration variant implements *last source wins* for identical dests (CLI specs override defaults-file entries) — a behavioural difference worth an explicit comment wherever a shared helper lands. A `dedup_ordered <nameref_out> <elements…>` plus a documented last-wins variant would remove the copies.

### 3. Slug normalisation (3 copies)

`project_slug` (`lib/naming.sh:10-21`) and `dest_slug` (`lib/naming.sh:39-51`) share a byte-for-byte identical normalisation body (lowercase, replace non-alphanumerics with `-`, collapse runs, strip edges). A third copy exists as `project_slug_e2e` (`test/e2e/helpers.bash:87-98`). A single `slugify` helper called by both naming functions would remove the drift risk (the two copies must stay in lockstep, since write-volume names embed `dest_slug` while container names embed `project_slug`).

### 4. Per-container naming (moderate, partially intentional)

`lib/naming.sh` defines twelve near-identical one-liner functions following `<slug>.<container>[.<kind>[.<extra>]]` (container names 27-37, worktree volumes 53-59, write volumes 61-67, root images 69-75), and `lib/containers.sh:41-73` adds a second dispatch layer (`container_name_of`, `root_image_of`, `worktree_volume_of`, `write_volume_of`) plus the direct `gitdir_volume`. A single parametric `resource_name <project> <container> <kind> [extra]` could replace both layers (~16 functions → 1). This is partially intentional — the named functions are self-documenting and individually unit-tested (`test/unit/naming.bats`) — so this is the weakest candidate in `lib/`; worth doing only if the naming scheme grows another dimension.

### 5. `onbox_action` vs `sandbox_action` (talkbox.sh)

`talkbox.sh:15-54` and `56-98` repeat the same skeleton: `parse_talkbox_options` → assemble mount/port/deny-allow arrays → `case "$TALKBOX_VERB"` dispatch. The two case tables differ only in executor names and the extra `write_srcs`/`write_dsts` arrays that onbox does not need. The dispatch tables are already drifting subtly: `onbox_action`'s `recontain` branch calls `ensure_base_image` explicitly (line 35) even though `run_recreate` performs the same probe internally for an onbox/base source (`lib/containers.sh:471-473`), while the sandbox branch relies on the internal probe. Unifying into one container-parameterised action — passing dummy arrays for onbox exactly as `run_onbox`/`run_recontain` already do in `lib/containers.sh:510-533` — would remove ~40 lines and one drift risk. Note the onbox branch also calls `ensure_base_image` before `run_onbox` (line 50) while `create_sandbox` does it again internally (`lib/containers.sh:425`) — harmless (idempotent) but duplicated responsibility.

### 6. `create_sandbox` vs `plan_recreate` (lib/containers.sh)

Both functions resolve the inheritance source and image (`lib/containers.sh:417-427` vs `467-474`), then run the identical commit → populate → gitdir-volume → `plan_container` → create sequence (`429-441` vs `226-241`, modulo planning vs execution). Extracting the shared "resolve source and image for container/project/rebuild" into one helper, and a shared populate→create plan assembler, would halve each. This is the largest remaining structural duplication in `lib/`.

### 7. `run_fetch` vs `run_merge` bundle lifecycle (lib/git.sh)

`run_fetch` (`lib/git.sh:123-154`) and `run_merge` (`lib/git.sh:204-222`) both create `mktemp -d "${TMPDIR:-/tmp}/talkbox-*.XXXXX"`, build `bundle_cmd`/`fetch_cmd` via `plan_fetch`, execute both in order, and `rm -rf` the temp dir on every exit path. A shared `bundle_fetch <project> <container> <bundle>` that owns the tmp-dir lifecycle would remove the copy-pasted cleanup and the early-return asymmetry (`run_merge` has three `rm -rf` calls; `run_fetch` has two). Relatedly, the `podman volume exists "$(gitdir_volume …)"` guard plus the error text `no git history for <c>; create the container first` is duplicated between `run_fetch` (`lib/git.sh:137-142`) and `require_git_history` (`lib/git.sh:194-197`) — `run_fetch` could call `require_git_history` (or a non-fatal probe variant) instead.

### 8. No-network run prefix and git mounts

The prefix `podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000` is spelled out in `gitdir_bundle_cmd` (`lib/git.sh:101`), `plan_volume_populate` (`lib/containers.sh:162`) and `container_sync_cmd` (`lib/containers.sh:589`). The git-mount quadruple (`/host/git:ro`, gitdir volume, worktree volume, `merge.sh:ro`) is likewise spelled out in both `plan_container` (`lib/containers.sh:132-135`) and `container_sync_cmd` (`lib/containers.sh:590-593`). Two small plan helpers (`plan_no_net_run`, `plan_git_mounts`) would centralise these token groups so the keep-id/userns triplet cannot drift between call sites.

### 9. Minor production items

- `install_nft_deny` (`lib/network.sh:142-174`) emits the same message twice per failure mode, differing only by the `warning:` prefix and return value; a small `fail_or_warn` helper would pair with the existing `nft_strict` predicate.
- `install_nft_deny_or_die` and `run_setup_in_container` (`lib/containers.sh:375-389`) share the "on failure stop the container and `die`" wrapper shape.
- `image/setup.sh:22,32` — the two branches differ only in the order of the `git remote add`/`set-url` fallback; a tiny `ensure_host_remote` would deduplicate.
- `talkbox.sh` `sandbox_action` (`talkbox.sh:63-64`) calls `mount_entries` for `write_srcs`/`write_dsts` and then `mount_volume_args`, which internally re-runs `mount_entries` on the same file and CLI specs (`lib/mounts.sh:117-133`). The write mounts are parsed twice per invocation; `mount_volume_args` could accept precomputed srcs/dsts (or one function could return all three outputs).
- **Intentional, do not "fix":** `warn()` in `lib/merge.sh:3-5` re-derives the `talkbox:` prefix from `die()` in `lib/common.sh` because `merge.sh` must stay location-agnostic and sourceable inside containers — it cannot depend on `common.sh`. Likewise the fifteen one-line `run_*` delegates (`lib/containers.sh:510-575`) are the deliberate dispatch surface documented in the map; replacing them with table dispatch would save little and cost greppability.

## Test harness

### 10. e2e setup/teardown boilerplate (7 files)

Every e2e file repeats:

```bash
PROJECT="$(mk_project)"; TALKBOX="$(mk_talkbox)"; ensure_base_image_e2e "$TALKBOX"
PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"   # + per-file CTR variables
teardown_talkbox "$PROJECT_SLUG" [extra]; rm -rf "$PROJECT" "$TALKBOX" [extras]
```

(`test/e2e/onbox.bats:3-14`, `netbox-offbox.bats:3-16`, `deny-allow.bats:3-21`, `lifecycle.bats:3-19`, `git-identity.bats:4-15`, `git-transport.bats:4-22`, `merge-sync.bats:4-22`). The only variance is which CTR variables are derived and whether `HOST_SRV_PID`/`EXTRA_DIRS` are tracked. A pair of parameterised `e2e_setup`/`e2e_teardown` helpers in `test/e2e/helpers.bash` would remove ~100 lines and, more importantly, keep the cleanup contract (kill server, `teardown_talkbox`, `rm -rf`) uniform — a new e2e file currently has to re-copy it correctly.

### 11. Helpers defined per file instead of shared

`volume_mountpoint()` is defined identically in `test/e2e/git-transport.bats:24-26` and `merge-sync.bats:24-26`; `container_stopped()` only in `merge-sync.bats:28-32`. Both belong in `test/e2e/helpers.bash`.

### 12. Inline podman shims (~14 copies) — largest single duplication cluster

Near-identical `cat >"$shimdir/podman" <<EOF … printf '%s\n' "\$*" >>'$log' … EOF` blocks are hand-written in:

- `test/unit/containers.bats:297-306, 329-341`
- `test/unit/netbox-offbox.bats:502-511, 534-540, 562-571, 601-607`
- `test/unit/lifecycle.bats:472-481, 495-500, 514-525, 544-555, 574-585`
- `test/unit/network.bats:386-390`
- `test/e2e/git-identity.bats:62-67`, `test/e2e/deny-allow.bats:105-110`

These re-implement variations of `make_podman_shim` (`test/unit/helpers.bash:13-79`, which already supports the PID inspect) and `mk_gpu_shim` (`test/e2e/helpers.bash:148-168`). The inline variants differ only in tiny knobs (echo a PID on inspect, fail on `setup.sh`, list `ext1` for `--external`, delegate to real podman). A parameterised shim factory — e.g. `make_podman_shim <dir> [--pid N] [--fail-on <pattern>] [--external id1 id2] [--delegate]` — would delete roughly 150 lines and make the shim's supported behaviours discoverable in one place.

Two related hazards:

- `test/unit/network.bats:334-363` **redefines `make_podman_shim`**, shadowing the helpers.bash function of the same name with a different implementation (different arguments, `SHIM_*` env instead of `PODMAN_*`). Which definition is live depends on load order within that file. See the linked issue below.
- The e2e logging-delegating shims (`git-identity.bats`, `deny-allow.bats`) are one flag away from `mk_gpu_shim`; folding them into one factory avoids a fourth family.

### 13. Unit-test per-file scaffolding (3 files)

`load_onbox_plan`/`load_netbox_plan`/`load_lifecycle_plan` (identical bodies), `setup()` (identical array initialisations), `use_podman_shim` (identical) and `plan_subcommands` (identical) are copied across `test/unit/containers.bats:4-31`, `netbox-offbox.bats:4-67` and `lifecycle.bats:4-78`; `array_contains`/`array_has_none` in `netbox-offbox.bats:11-33` overlap with `line_has_token` in helpers. Moving these into `test/unit/helpers.bash` (which exists but currently only carries the shim and line assertions) would leave each bats file with only its tests. The `load_*_plan` indirection exists only because `load_lib` cannot be called at file scope — a `load_container_libs` helper in helpers.bash would serve all three.

### 14. HTTP-server readiness loop (4 copies)

```bash
for ((n = 0; n < 20; n++)); do
    curl -fsS --max-time 2 "http://127.0.0.1:$port/marker" >/dev/null 2>&1 && break
    sleep 0.5
done
```

appears in `test/e2e/deny-allow.bats:52-57, 79-84, 136-141` (the IPv6 variant) and `lifecycle.bats:78-83`, always immediately after `start_host_http_server`. A `wait_for_http <url>` (or an optional readiness wait inside `start_host_http_server`, which already polls for the port line) would remove all four.

### 15. `sdrun bash -c 'cd "$1" && …'` idiom (~15 sites)

`run_talkbox`/`run_onbox_noninteractive` exist for the common cases, but ~15 e2e invocations hand-roll the `sdrun bash -c 'cd "$1" && … talkbox.sh … "$2" …'` wrapper with per-site `# shellcheck disable=SC2016` comments (`test/e2e/onbox.bats:74,82,92,118`, `netbox-offbox.bats:104,118`, `deny-allow.bats:112,119,124`, `lifecycle.bats:51,55,64,85,101,115,124`, `git-identity.bats:69`). One generalised `run_talkbox_args <project> <talkbox> <container> [args…]` in helpers would cover almost all of them.

### 16. Container-fold and verb-fold test repetition

- `test/unit/lifecycle.bats:507-595` — three byte-identical "rm_image prunes external containers" tests differing only in `onbox`/`netbox`/`offbox` and the name helper; a `for c in onbox netbox offbox` loop inside one test (as `git-transport.bats:92` already does) is the established in-repo pattern.
- `test/unit/netbox-offbox.bats:556-631` — each recontain/rebuild ordering test duplicates its assertion block twice internally (recontain, then `: >"$log"`, then rebuild).
- `test/e2e/git-identity.bats` — six tests = the same two assertions × three containers.
- The `grep -n <pat> "$log" | head -n 1 | cut -d: -f1` line-number extraction idiom appears ~40 times across these files; `podman_line_no` (`test/unit/helpers.bash:87-89`) already implements it for the `PODMAN_LOG` case, and a generic `log_line_no <pattern> <file>` would cover the local-`$log` sites.

Bats tests are deliberately explicit, so some repetition is fine — but the above copies are byte-identical apart from a container name, which is exactly the kind of repetition a loop expresses better (and which already has precedent in this suite).

## Prioritised recommendations

1. **Shim factory** (§12): highest payoff — ~14 hand-written copies across both suites plus a name-shadowing hazard. Centralise in `test/unit/helpers.bash` / `test/e2e/helpers.bash`.
2. **e2e setup/teardown + shared helpers** (§10, §11, §14, §15): one `e2e_setup`/`e2e_teardown` pair plus `wait_for_http` and a general `run_talkbox_args`; removes ~150 lines and makes cleanup uniform.
3. **`read_list_file` + `dedup_ordered`** (§1, §2): five and four copies respectively in production code; small, well-tested seam in `lib/common.sh`.
4. **`slugify`** (§3): three copies including one in tests; cheap and removes a silent-drift risk.
5. **`bundle_fetch` + `require_git_history` reuse** (§7): removes duplicated tmp-dir lifecycle and a duplicated error path in `lib/git.sh`.
6. **Unit-test scaffolding consolidation** (§13): move `plan_subcommands`, `use_podman_shim`, array-init `setup` and a `load_container_libs` into `test/unit/helpers.bash`.
7. **`create_sandbox`/`plan_recreate` convergence** (§6) and **action unification in `talkbox.sh`** (§5): larger refactors with behavioural edge cases; do only with the full test suite as a safety net.
8. **Naming table** (§4) and the minor items in §9: optional, low priority.

## Related issue documents

- [make_podman_shim shadowing in network.bats](../issues/make-podman-shim-shadowed-in-network-bats.gen.md)
- [MAP.gen.md is missing implemented core test files](../issues/map-gen-md-missing-test-files.gen.md)
