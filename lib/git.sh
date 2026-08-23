# shellcheck shell=bash
# shellcheck disable=SC2178 # nameref parameters refer to caller-declared arrays

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"

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

list_submodule_git_dirs() {
	local project="$1" gitdir modules
	gitdir="$(resolve_git_dir "$project")"
	modules="$gitdir/modules"
	if [[ -d "$modules" ]]; then
		find "$modules" -mindepth 1 -maxdepth 1 -type d -print | sort
	fi
}

git_mounts_enabled() {
	local project="$1"
	git_tracked "$project" && [[ "$(classify_git_dir "$project")" == inside ]]
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

gitdir_bundle_cmd() {
	local -n _out="$1"
	local project="$2" container="$3" bundle="$4"
	_out+=("podman" "run" "--rm" "--network=none" "--userns=keep-id:uid=1000,gid=1000")
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
	local -n _out="$1"
	local project="$2" container="$3" bundle="$4"
	local -a parts=()
	gitdir_bundle_cmd parts "$project" "$container" "$bundle"
	host_fetch_cmd parts "$bundle" "$container"
	_out=("${parts[@]}")
}

execute_fetch_plan() {
	local -a plan=("$@")
	local -a cmd=()
	local i arg
	for ((i = 0; i < ${#plan[@]}; i++)); do
		arg="${plan[$i]}"
		if [[ "$arg" == git && "${plan[$((i + 1))]}" == fetch ]] && ((${#cmd[@]} > 0)); then
			"${cmd[@]}"
			cmd=()
		fi
		cmd+=("$arg")
	done
	if ((${#cmd[@]} > 0)); then
		"${cmd[@]}"
	fi
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
	local tmp bundle c rc=0
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/talkbox-fetch.XXXXXX")"
	for c in "${containers[@]}"; do
		if ! podman volume exists "$(gitdir_volume "$project" "$c")" >/dev/null 2>&1; then
			if [[ "$all" == yes ]]; then
				continue
			fi
			rm -rf "$tmp"
			die "no git history for $c; create the container first" 1
		fi
		bundle="$tmp/$c.bundle"
		local -a plan=()
		plan_fetch plan "$project" "$c" "$bundle"
		if ! execute_fetch_plan "${plan[@]}"; then
			rc=1
			break
		fi
	done
	rm -rf "$tmp"
	return "$rc"
}
