# shellcheck shell=bash
# shellcheck disable=SC2178 # nameref parameters refer to caller-declared arrays

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"
source "$TALKBOX_ROOT/lib/merge.sh"

git_tracked() {
	local project="$1"
	[[ -e "$project/.git" ]]
}

resolve_git_dir() {
	local project="$1" dotgit line
	project="$(readlink -f "$project")"
	dotgit="$project/.git"
	if [[ -f "$dotgit" ]]; then
		IFS= read -r line <"$dotgit" || true
		line="${line#gitdir: }"
		line="$(trim "$line")"
		if [[ -z "$line" ]]; then
			printf '%s\n' "$dotgit"
		elif [[ "$line" == /* ]]; then
			readlink -f "$line"
		else
			readlink -f "$project/$line"
		fi
	else
		printf '%s\n' "$dotgit"
	fi
}

classify_git_dir() {
	local project="$1" gitdir canonical
	if ! git_tracked "$project"; then
		printf 'none\n'
		return
	fi
	gitdir="$(resolve_git_dir "$project")"
	canonical="$(readlink -f "$project")"
	if [[ "$gitdir" == "$canonical" || "$gitdir" == "$canonical"/* ]]; then
		printf 'inside\n'
	else
		printf 'outside\n'
	fi
}

git_mounts_enabled() {
	local project="$1"
	git_tracked "$project" && [[ "$(classify_git_dir "$project")" == inside ]]
}

host_git_identity() {
	local project="$1" field="${2:-}" name email
	if [[ -z "$field" || "$field" == user.name ]]; then
		name="$(git -C "$project" config user.name 2>/dev/null || true)"
		if [[ -n "$name" ]]; then
			printf '%s\n' "$name"
		fi
	fi
	if [[ -z "$field" || "$field" == user.email ]]; then
		email="$(git -C "$project" config user.email 2>/dev/null || true)"
		if [[ -n "$email" ]]; then
			printf '%s\n' "$email"
		fi
	fi
}

refuse_outside_gitdir() {
	local project="$1"
	if git_tracked "$project" && [[ "$(classify_git_dir "$project")" == outside ]]; then
		die "the git directory of $project lies outside the project; refusing to mount" 1
	fi
}

absorb_submodules() {
	local project="$1"
	git_tracked "$project" || return 0
	git -C "$project" submodule absorbgitdirs 2>/dev/null || true
}

prepare_git_host() {
	local project="$1"
	refuse_outside_gitdir "$project"
	absorb_submodules "$project"
}

plan_git_mounts() {
	local -n _out="$1"
	local project="$2" container="$3"
	shift 3
	local base mount
	base="$(project_base "$project")"
	for mount in "$@"; do
		case "$mount" in
		hostgit) _out+=("-v" "$(resolve_git_dir "$project"):/host/git:ro") ;;
		gitdir) _out+=("-v" "$(gitdir_volume "$project" "$container"):/working/$base/.git") ;;
		merge) _out+=("-v" "$TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro") ;;
		esac
	done
}

gitdir_bundle_cmd() {
	local -n _out="$1"
	local project="$2" container="$3" bundle="$4"
	plan_no_net_run "${!_out}"
	_out+=("-v" "$(gitdir_volume "$project" "$container"):/gitdir:ro")
	_out+=("-v" "$(dirname "$bundle"):/host/bundle")
	_out+=("-e" "GIT_DIR=/gitdir")
	_out+=("$(base_image_name)")
	_out+=("git" "bundle" "create" "/host/bundle/$(basename "$bundle")" "--all")
}

host_fetch_cmd() {
	local -n _out="$1"
	local bundle="$2" container="$3"
	_out+=("git" "fetch" "$bundle" "+refs/heads/*:refs/remotes/$container/*")
}

plan_fetch() {
	local -n _bundle_cmd="$1"
	local -n _fetch_cmd="$2"
	local project="$3" container="$4" bundle="$5"
	gitdir_bundle_cmd _bundle_cmd "$project" "$container" "$bundle"
	host_fetch_cmd _fetch_cmd "$bundle" "$container"
}

run_bundle_fetch() {
	local project="$1" container="$2" prefix="$3"
	local tmp bundle rc=0
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/talkbox-$prefix.XXXXXX")"
	bundle="$tmp/$container.bundle"
	local -a bundle_cmd=() fetch_cmd=()
	plan_fetch bundle_cmd fetch_cmd "$project" "$container" "$bundle"
	if ! "${bundle_cmd[@]}" || ! "${fetch_cmd[@]}"; then
		rc=1
	fi
	rm -rf "$tmp"
	return "$rc"
}

run_fetch() {
	local project="$1" container="$2" all="$3"
	if ! git_tracked "$project"; then
		die "not a git repository: $project" 1
	fi
	local -a containers=()
	if [[ "$all" == yes ]]; then
		containers=(onbox netbox offbox)
	else
		containers=("$container")
	fi
	local c rc=0
	for c in "${containers[@]}"; do
		if [[ "$all" == yes ]]; then
			gitdir_volume_exists "$project" "$c" || continue
		else
			require_gitdir_volume "$project" "$c"
		fi
		if ! run_bundle_fetch "$project" "$c" fetch; then
			rc=1
			break
		fi
	done
	return "$rc"
}

remote_branches() {
	local remote="$1"
	git for-each-ref --format='%(refname:strip=3)' "refs/remotes/$remote/"
}

host_branches() {
	git for-each-ref --format='%(refname:strip=2)' refs/heads/
}

current_branch() {
	git symbolic-ref --short HEAD 2>/dev/null ||
		die "cannot determine the current branch: HEAD is detached" 1
}

resolve_branches() {
	local -n _out="$1"
	local all="$2" branch="$3" remote="${4:-}"
	local -a listed=()
	if [[ "$all" == yes ]]; then
		if [[ -n "$remote" ]]; then
			mapfile -t listed < <(remote_branches "$remote")
		else
			mapfile -t listed < <(host_branches)
		fi
		_out=("${listed[@]}")
	else
		if [[ -z "$branch" ]]; then
			branch="$(current_branch)"
		fi
		_out=("$branch")
	fi
}

gitdir_volume_exists() {
	podman volume exists "$(gitdir_volume "$1" "$2")" >/dev/null 2>&1
}

require_gitdir_volume() {
	local project="$1" container="$2"
	if ! gitdir_volume_exists "$project" "$container"; then
		die "no git history for $container; create the container first" 1
	fi
}

require_git_history() {
	local project="$1" container="$2" vol mountpoint
	if ! git_tracked "$project"; then
		die "not a git repository: $project" 1
	fi
	require_gitdir_volume "$project" "$container"
	vol="$(gitdir_volume "$project" "$container")"
	mountpoint="$(podman volume inspect --format '{{.Mountpoint}}' "$vol" 2>/dev/null)"
	if [[ -z "$mountpoint" || ! -e "$mountpoint/HEAD" ]]; then
		die "no git history in the $container gitdir volume; start the container first" 1
	fi
}

run_merge() {
	local project="$1" container="$2" all="$3" branch="$4"
	require_git_history "$project" "$container"
	run_bundle_fetch "$project" "$container" merge || return 1
	local -a branches=() b
	resolve_branches branches "$all" "$branch" "$container"
	for b in "${branches[@]}"; do
		custom_merge "$container" "$b" || return 1
	done
}

# shellcheck disable=SC2016 # $@ and $b expand inside the container at run time
sync_script() {
	printf 'source /talkbox/lib/merge.sh\n'
	printf 'git fetch host || exit 1\n'
	printf 'for b in "$@"; do custom_merge host "$b" || exit 1; done\n'
}

run_sync() {
	local project="$1" container="$2" all="$3" branch="$4"
	require_git_history "$project" "$container"
	local -a branches=()
	resolve_branches branches "$all" "$branch"
	if ((${#branches[@]} == 0)); then
		return 0
	fi
	run_sync_in_container "$project" "$container" "$(sync_script)" "${branches[@]}"
}
