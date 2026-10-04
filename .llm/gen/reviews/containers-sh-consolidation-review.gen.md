# Review: consolidation of repeated `onbox`/`netbox`/`offbox` logic in `lib/containers.sh`

## Summary

Yes — consolidation is suitable, and the file is past the point where the duplication pays for itself. [lib/containers.sh](lib/containers.sh) (913 lines) encodes the three-container symmetry by copy-paste: **twelve function families exist in two or three near-identical copies**, and roughly 350–400 lines (~40% of the file) are repeated code. What actually differs between `onbox`, `netbox` and `offbox` is small and enumerable (§3); everything else is repeated verbatim.

The file's own history demonstrates the cost of this structure. Three previously documented issues — [planner/executor divergence](.llm/gen/issues/planner-executor-divergence.gen.md), [dead `_deny` namerefs in plan functions](.llm/gen/issues/dead-deny-nameref-in-plan-functions.gen.md) and [orphaned named volumes after lifecycle verbs](.llm/gen/issues/lifecycle-verbs-leave-named-volumes-orphaned.gen.md) — each record a case where the copies drifted apart or a fix had to be applied at many parallel sites. All three have since been repaired in the current revision, but the copy-paste structure that produced the drift remains. Adding one new global mount or env var today requires editing all three create-args planners (e.g. the `defaults/art` mount appears at lines 96–98, 405–407 and 460–462).

Recommended shape: **one parameterized core per family** (`plan_container`, `plan_recreate`, `run_container`, `run_recreate`, `create_sandbox`, unified rm verbs), with the existing per-container function names retained as one-to-three-line wrappers. The wrappers preserve every interface pinned by unit tests and the dynamic dispatch in [talkbox.sh](talkbox.sh), so test churn is zero. Expected result: ~913 → ~550 lines with a single edit site per cross-cutting concern.

## Scope and baseline

- Reviewed [lib/containers.sh](lib/containers.sh) at HEAD against its only production consumer [talkbox.sh](talkbox.sh) (sources it and dispatches `run_${container}_*` dynamically at lines 81–95) and the naming helpers in [lib/naming.sh](lib/naming.sh).
- Unit tests invoke the plan functions **by name**: `plan_onbox` (~20 sites in [test/unit/containers.bats](test/unit/containers.bats)), `plan_netbox`/`plan_offbox`/`plan_volume_populate`/`plan_netbox_populate`/`plan_offbox_populate`/`plan_netbox_recontain`/`plan_offbox_recontain`/`plan_netbox_rebuild`/`plan_offbox_rebuild`/`run_netbox_recontain`/`run_offbox_recontain`/`run_netbox_rebuild`/`run_offbox_rebuild`/`inherit_source` ([test/unit/netbox-offbox.bats](test/unit/netbox-offbox.bats)), `plan_recontain`/`plan_rebuild`/`plan_rm_container`/`plan_rm_image` ([test/unit/lifecycle.bats](test/unit/lifecycle.bats)), `run_sync_in_container` ([test/unit/git-transport.bats](test/unit/git-transport.bats)).
- `make test-unit` was run during this review: **278/278 pass**, so the unit suite is a verified green baseline for a refactor. The e2e suite additionally exercises the lifecycle verbs externally through the CLI.

## What actually differs between the three containers

This is the complete variation space; everything else in the file is invariant.

| Variation point | onbox | netbox | offbox |
|---|---|---|---|
| container name | `onbox_container_name` | `netbox_container_name` | `offbox_container_name` |
| `TALKBOX_CONTAINER_TYPE` env | `onbox` | `netbox` | `offbox` |
| image used at create | always `$(base_image_name)` | `$image` (root or base) | `$image` (root or base) |
| worktree mount source | `$project` (bind-mount) | `netbox_worktree_volume` | `offbox_worktree_volume` |
| pasta suffix | `--dns-forward,169.254.1.1,--map-guest-addr,none` | same as onbox | `-i,lo,-I,talkbox0` |
| root image | none | `netbox_root_image` | `offbox_root_image` |
| nft deny step after start | yes | yes | no (no-op anyway, see §7.1) |
| volume population | none | host → volume | netbox volume → volume, else host → volume |
| write mounts | bind-mounts | write volumes | write volumes |

## Duplication inventory

| # | Functions (lines) | Size each | Actual differences |
|---|---|---|---|
| 1 | `plan_onbox` (59–111), `plan_netbox` (367–420), `plan_offbox` (422–475) | ~53 lines | 5 variation points (§3); ~45 of 53 lines byte-identical |
| 2 | pasta `net`/`port_list` block at 65–72, 374–381, 430–436 | 8 lines | onbox ≡ netbox; offbox differs only in the suffix string |
| 3 | `plan_recontain` (113–125), `plan_rebuild` (127–140) | ~13 lines | one `podman build` line |
| 4 | `plan_netbox_recontain` (477–500), `plan_offbox_recontain` (502–525), `plan_netbox_rebuild` (527–551), `plan_offbox_rebuild` (553–577) | ~24 lines | container type; build line; populate signature (offbox takes `$source`) |
| 5 | `plan_netbox_rm_container` (579–586), `plan_offbox_rm_container` (588–595) | 8 lines | container type only |
| 6 | `plan_netbox_rm_image` (597–599), `plan_offbox_rm_image` (601–603) | 3 lines | pure pass-throughs to `plan_rm_image` |
| 7 | `plan_netbox_populate` (618–631), `plan_offbox_populate` (633–657) | 14/25 lines | shared loop shape; offbox adds the netbox-volume fallback (semantic, see §5.7) |
| 8 | `create_netbox` (659–680), `create_offbox` (682–703) | 22 lines | container type; populate signature |
| 9 | `run_onbox` (228–257), `run_netbox` (705–729), `run_offbox` (731–754) | ~25 lines | create branch; offbox skips nft; exec/stop/return tail identical ×3 (717–728 ≡ 742–753 ≡ 245–256) |
| 10 | `run_netbox_recontain` (756–772), `run_offbox_recontain` (774–789), `run_netbox_rebuild` (791–804), `run_offbox_rebuild` (806–818) | ~15 lines | container type; nft step; `ensure_base_image` only in recontain |
| 11 | `run_netbox_rm_container` (820–834), `run_offbox_rm_container` (836–850) | 15 lines | container type only |
| 12 | `run_rm_image` (286–298), `run_netbox_rm_image` (852–864), `run_offbox_rm_image` (866–878) | 13 lines | container name used for the in-use check only |

Micro-fragments repeated across families:

- `podman stop -t "$STOP_GRACE_SECONDS" … || true` — **11 sites** (194, 202, 255, 266, 276, 727, 752, 771, 788, 803, 817).
- `podman rm -f --volumes <ctr>` — **14 sites** (119, 134, 147, 293, 491, 516, 542, 567, 583, 592, 830, 846, 859, 873).
- `inherit_source <type> "$(exists_yn …)" ×3 "$TALKBOX_FRESH" "$TALKBOX_INHERIT"` — **6 sites** (664, 687, 762, 780, 797, 812), each a three-line command substitution with four nested `exists_yn` calls.
- commit-or-base image selection (`image="$root"; if [[ "$source" != base ]] … else image="$(base_image_name)"`) — **6 sites** (486–490, 511–515, 537–541, 563–567 planned; 665–671, 688–694 executed immediately).
- the base-image `podman build` command — **4 sites** (133, 177, 536, 562).
- type-dispatch `case` statements that a naming helper could absorb: `plan_container_volumes_rm` (46–56), `container_sync_cmd` (894–898). `container_name_of` (344–351) is the existing model for this.

## Proposed consolidation

### 5.1 `pasta_net` — network string (cluster 2)

```bash
pasta_net() {
	local suffix="$1"
	shift
	local -n _ports="$1"
	local net="pasta" port_list
	if ((${#_ports[@]} > 0)); then
		printf -v port_list '%s,' "${_ports[@]}"
		net+=":${port_list%,},$suffix"
	else
		net+=":$suffix"
	fi
	printf '%s\n' "$net"
}
```

onbox/netbox pass `--dns-forward,169.254.1.1,--map-guest-addr,none`; offbox passes `-i,lo,-I,talkbox0` (a `container_net_suffix "$container"` wrapper removes even that repetition).

### 5.2 `plan_container` — unified create-args planner (clusters 1, 2)

One function replacing the three ~53-line planners, parameterized by container type and image. Put the image argument last so the netbox/offbox wrappers pass through unchanged and onbox appends its constant:

```bash
plan_container() {
	local -n _plan_out="$1"
	local container="$2" project="$3" interactive="$4"
	local -n _read="$5" _write="$6" _ports="$7"
	local image="${8:-$(base_image_name)}"
	local base worktree
	base="$(project_base "$project")"
	case "$container" in
	onbox) worktree="$project" ;;
	*) worktree="$("${container}_worktree_volume" "$project")" ;;
	esac
	# … single copy of: workdir, userns, network, cap-drops, --init,
	#    GPU block, slug/type env, worktree mount, git-mount block,
	#    setup.sh, dotfiles, read/write arrays, --name, interactive, image, sleep
}

plan_onbox() { plan_container onbox "$@" "$(base_image_name)"; }
plan_netbox() { plan_container netbox "$@"; }
plan_offbox() { plan_container offbox "$@"; }
```

The `"${container}_worktree_volume"` dynamic call follows the dispatch idiom [talkbox.sh](talkbox.sh) already uses (`"run_${container}_recontain"`). This is the single largest win (~100 duplicated lines) and the most mechanical: the unit tests assert exact `podman` argument sequences, and the wrappers keep those assertions valid.

### 5.3 Naming dispatch helpers (micro-fragments)

`container_name_of` already exists; add its siblings so the remaining `case` dispatches collapse:

- `root_image_of <container> <project>` — `netbox_root_image`/`offbox_root_image`
- `worktree_volume_of <container> <project>`
- `write_volume_of <container> <project> <dest-slug>`

`plan_container_volumes_rm` (41–57) then loses both `case` blocks and becomes a flat loop; `container_sync_cmd`'s mount `case` (894–898) collapses to one line.

### 5.4 `plan_recreate` — unified lifecycle plan (clusters 3, 4)

The onbox pair and the sandbox quartet share one shape: *[build]* → *[commit source]* → `rm` container → remove volumes → *[populate volumes]* → create gitdir volume → `create` → `start`. One function with `container` and a `rebuild` flag covers all six, using `container_name_of`, `root_image_of` and `"plan_${container}_populate"` dispatch. Two signature normalizations are needed first: `plan_offbox_populate` takes a `root_source` argument that `plan_netbox_populate` lacks (give netbox the same argument, ignored, or resolve source selection per-dest), and the onbox wrappers must supply the dummy `srcs`/`dsts` arrays — the `local -a no_write_dsts=()` idiom already in use at lines 117, 131 and 146 generalizes to this.

### 5.5 `run_container` and `exec_in_container` (cluster 9)

Extract the byte-identical 11-line exec/stop/return tail (245–256) into `exec_in_container <ctr> <command> <interactive>`, used by all three `run_*`. The full unification then needs only a per-type create branch (onbox creates inline; netbox/offbox call `create_sandbox`), and the start→nft→setup→exec→stop sequence can be shared (§7.1).

### 5.6 `run_recreate`, `create_sandbox`, unified rm verbs (clusters 8, 10, 11, 12)

- `create_sandbox <container> …` replaces `create_netbox`/`create_offbox`.
- `run_recreate <container> <rebuild> …` replaces the four sandbox executors; the onbox `run_recontain`/`run_rebuild` become wrappers or fold in directly.
- `run_rm_image_any <container> <project>` replaces the triple; `container_name_of` supplies the only varying input, and the `plan_netbox_rm_image`/`plan_offbox_rm_image` pass-throughs are deleted. Note `plan_rm_image`'s `in_use` parameter is vestigial — all three callers pass `no` because the real check is the imperative `image_in_use` + `die` — so it can be dropped at the same time.
- `run_rm_container_any <container>` replaces the netbox/offbox pair (the plan-level pair in cluster 5 collapses into it via `root_image_of`).

### 5.7 What not to consolidate

`plan_netbox_populate` vs `plan_offbox_populate` differ *semantically* — offbox's netbox-volume fallback **is** the read-write-volume inheritance policy from [SPEC.md](SPEC.md) ("read-write volume inheritence"). Keep the policy explicit in `plan_offbox_populate`; at most share the loop skeleton. Likewise `inherit_source`/`source_exists` are already the correct shared abstraction for the root-filesystem inheritance matrix and need no change.

## Interface and test impact

Two strategies:

1. **Wrapper preservation (recommended).** Consolidate the internals; keep every existing function name as a 1–3 line delegate (as sketched in §5.2). Zero test churn, [talkbox.sh](talkbox.sh)'s `"run_${container}_*"` dispatch keeps working, and the ~15 shims cost perhaps 40 lines total.
2. **Full parameterization.** Change [talkbox.sh](talkbox.sh) to call `run_container onbox …` etc. and update the unit tests (~100 call-site edits across [test/unit/containers.bats](test/unit/containers.bats), [test/unit/netbox-offbox.bats](test/unit/netbox-offbox.bats), [test/unit/lifecycle.bats)). Cleaner end state, but it rewrites tests that currently pin correct behaviour for little additional safety.

Given the project guidance to prefer minimal, targeted changes, strategy 1 delivers nearly all the benefit at a fraction of the risk.

## Behavioural invariants to preserve

1. **offbox and nft.** `run_offbox` never calls `install_nft_deny_or_die`. This is behaviorally a no-op difference: [talkbox.sh](talkbox.sh) only fills the deny/allow arrays for onbox (line 22) and netbox (lines 66–68), and `install_nft_deny` returns 0 immediately for an empty deny set ([lib/network.sh](lib/network.sh) lines 145–147 — verified). A unified `run_container` may therefore call the wrapper unconditionally, but this should be confirmed by the e2e suite after the change.
2. **Base-image availability.** Recontain paths ensure the base image exists before planning (`ensure_base_image` at [talkbox.sh](talkbox.sh) line 35 for onbox; `run_netbox_recontain`/`run_offbox_recontain` lines 763–765/781–783 only when `source == base`); rebuild paths build it *inside* the plan. A unified `run_recreate` must keep this distinction.
3. **Commit-before-rm ordering** in the recontain/rebuild plans (487→491, 512→516, 538→542, 564→568): the inheritance source may be the very container being removed.
4. **`create_netbox`/`create_offbox` execute `podman commit` immediately** (666, 689) rather than planning it. Unifying on the planned form is safe (the target container does not exist on this path, so no `rm` races the commit) provided the commit stays first in the plan.
5. **onbox volume set.** `plan_container_volumes_rm`'s `case` encodes that onbox removes only the gitdir volume while netbox/offbox also remove worktree and write volumes.
6. **Conditional root-image removal.** `run_netbox_rm_container`/`run_offbox_rm_container` `rmi` the root image only when it exists (827–832, 843–848); the fallback path omits it.
7. **`run_onbox`'s eager gitdir volume creation** (236) vs the planned creation in `create_netbox`/`create_offbox` (674, 697) — both precede `podman create`, and podman auto-creates named volumes referenced with `-v` anyway, so the planned form is the one to keep.

## Suggested sequencing

1. `run_rm_image` family + `stop_container`/`plan_container_rm` micro-helpers — smallest, zero semantic variation, immediate readability gain.
2. `pasta_net` + `plan_container` with wrappers (§5.2) — largest win, fully unit-pinned.
3. Naming dispatch helpers (§5.3) + `plan_recreate` (§5.4).
4. `exec_in_container` + `run_container` (§5.5), with the offbox/nft unification verified against e2e.
5. `create_sandbox`, `run_recreate`, unified rm-container (§5.6).
6. Optional: populate loop-skeleton sharing (§5.7).

After each step run `make test-unit`, `make test-e2e`, `make lint` and `make format` ([SPEC.md](SPEC.md) requires shellcheck + shfmt). Note that consolidation also retires several `# shellcheck disable=SC2034` pragmas (e.g. line 145) and the `SC2178` file-level disable becomes less necessary as nameref plumbing is centralised.

## Related

- [Repository review](.llm/gen/reviews/repository-review.gen.md) — previously assessed this duplication as "acceptable for clarity … the most obvious candidate for future consolidation"; this review is that analysis.
- [Planner/executor divergence](.llm/gen/issues/planner-executor-divergence.gen.md), [dead `_deny` namerefs](.llm/gen/issues/dead-deny-nameref-in-plan-functions.gen.md), [orphaned named volumes](.llm/gen/issues/lifecycle-verbs-leave-named-volumes-orphaned.gen.md) — historical copy-drift in this file, since repaired, cited as evidence of maintenance cost.
