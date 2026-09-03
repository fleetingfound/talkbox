# shellcheck shell=bash
# shellcheck disable=SC2178 # _plan_out is a nameref to a caller-declared array

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"
source "$TALKBOX_ROOT/lib/git.sh"

STOP_GRACE_SECONDS=5

plan_gitdir_volume() {
	local -n _plan_out="$1"
	local project="$2" container="$3" vol
	vol="$(gitdir_volume "$project" "$container")"
	if git_mounts_enabled "$project" && ! volume_exists "$vol"; then
		_plan_out+=("podman" "volume" "create" "$vol")
	fi
}

plan_git_identity_env() {
	local -n _plan_out="$1"
	local project="$2" name email
	name="$(host_git_identity "$project" user.name)"
	email="$(host_git_identity "$project" user.email)"
	if [[ -n "$name" ]]; then
		_plan_out+=("--env" "TALKBOX_GIT_USER_NAME=$name")
	fi
	if [[ -n "$email" ]]; then
		_plan_out+=("--env" "TALKBOX_GIT_USER_EMAIL=$email")
	fi
}

plan_volume_rm() {
	local -n _plan_out="$1"
	local vol="$2"
	if volume_exists "$vol"; then
		_plan_out+=("podman" "volume" "rm" "-f" "$vol")
	fi
}

plan_container_volumes_rm() {
	local -n _plan_out="$1"
	local project="$2" container="$3"
	local -n _dsts="$4"
	local i
	case "$container" in
	netbox) plan_volume_rm "${!_plan_out}" "$(netbox_worktree_volume "$project")" ;;
	offbox) plan_volume_rm "${!_plan_out}" "$(offbox_worktree_volume "$project")" ;;
	esac
	plan_volume_rm "${!_plan_out}" "$(gitdir_volume "$project" "$container")"
	for ((i = 0; i < ${#_dsts[@]}; i++)); do
		case "$container" in
		netbox) plan_volume_rm "${!_plan_out}" "$(netbox_write_volume "$project" "$(dest_slug "${_dsts[$i]}")")" ;;
		offbox) plan_volume_rm "${!_plan_out}" "$(offbox_write_volume "$project" "$(dest_slug "${_dsts[$i]}")")" ;;
		esac
	done
}

plan_onbox() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _ports="$6"
	local base net port_list
	base="$(project_base "$project")"
	net="pasta"
	if ((${#_ports[@]} > 0)); then
		printf -v port_list '%s,' "${_ports[@]}"
		port_list="${port_list%,}"
		net+=":$port_list"
	fi
	_plan_out+=("--workdir=/working/$base")
	_plan_out+=("--userns=keep-id:uid=1000,gid=1000")
	_plan_out+=("--network=$net")
	_plan_out+=("--cap-drop=NET_ADMIN")
	_plan_out+=("--cap-drop=NET_RAW")
	_plan_out+=("--init")
	if [[ "$TALKBOX_GPU" == yes ]]; then
		_plan_out+=("--device" "nvidia.com/gpu=all")
		_plan_out+=("--group-add" "keep-groups")
	fi
	_plan_out+=("--env" "TALKBOX_PROJECT_SLUG=$(project_slug "$project")")
	_plan_out+=("--env" "TALKBOX_CONTAINER_TYPE=onbox")
	_plan_out+=("-v" "$project:/working/$base")
	if git_mounts_enabled "$project"; then
		_plan_out+=("-v" "$(resolve_git_dir "$project"):/host/git:ro")
		_plan_out+=("-v" "$(gitdir_volume "$project" onbox):/working/$base/.git")
		_plan_out+=("-v" "$TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro")
		plan_git_identity_env "${!_plan_out}" "$project"
	fi
	if [[ -d "$TALKBOX_ROOT/defaults/dotfiles" ]]; then
		_plan_out+=("-v" "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro")
	fi
	if [[ -d "$project/.dotfiles" ]]; then
		_plan_out+=("-v" "$project/.dotfiles:/talkbox/dotfiles.project:ro")
	fi
	_plan_out+=("${_read[@]}")
	_plan_out+=("${_write[@]}")
	_plan_out+=("--name=$(onbox_container_name "$project")")
	if [[ "$interactive" == yes ]]; then
		_plan_out+=("--interactive")
		_plan_out+=("--tty")
	fi
	_plan_out+=("$(base_image_name)")
	_plan_out+=("sleep" "infinity")
}

plan_recontain() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _ports="$6"
	# shellcheck disable=SC2034 # consumed by nameref parameter
	local -a create_args=() no_write_dsts=()
	plan_onbox create_args "$project" "$interactive" "$4" "$5" "$6"
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(onbox_container_name "$project")")
	plan_container_volumes_rm "${!_plan_out}" "$project" onbox no_write_dsts
	plan_gitdir_volume "${!_plan_out}" "$project" onbox
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$(onbox_container_name "$project")")
}

plan_rebuild() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _ports="$6"
	# shellcheck disable=SC2034 # consumed by nameref parameter
	local -a create_args=() no_write_dsts=()
	plan_onbox create_args "$project" "$interactive" "$4" "$5" "$6"
	_plan_out+=("podman" "build" "-t" "$(base_image_name)" "-f" "$TALKBOX_ROOT/image/Containerfile" "$TALKBOX_ROOT/image")
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(onbox_container_name "$project")")
	plan_container_volumes_rm "${!_plan_out}" "$project" onbox no_write_dsts
	plan_gitdir_volume "${!_plan_out}" "$project" onbox
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$(onbox_container_name "$project")")
}

plan_rm_container() {
	local -n _plan_out="$1"
	local project="$2"
	# shellcheck disable=SC2034 # consumed by nameref parameter
	local -a no_write_dsts=()
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(onbox_container_name "$project")")
	plan_container_volumes_rm "${!_plan_out}" "$project" onbox no_write_dsts
}

plan_rm_image() {
	local -n _plan_out="$1"
	local project="$2" in_use="$3"
	if [[ "$in_use" == no ]]; then
		_plan_out+=("podman" "rmi" "$(base_image_name)")
	fi
}

execute_plan() {
	local -a plan=("$@")
	local -a cmd=()
	local arg
	for arg in "${plan[@]}"; do
		if [[ "$arg" == podman ]] && ((${#cmd[@]} > 0)); then
			"${cmd[@]}"
			cmd=()
		fi
		cmd+=("$arg")
	done
	if ((${#cmd[@]} > 0)); then
		"${cmd[@]}"
	fi
}

ensure_base_image() {
	if ! podman image exists "$(base_image_name)" >/dev/null 2>&1; then
		podman build -t "$(base_image_name)" -f "$TALKBOX_ROOT/image/Containerfile" "$TALKBOX_ROOT/image"
	fi
}

container_exists() {
	local ctr="$1"
	podman container exists "$ctr" 2>/dev/null
}

container_running() {
	local ctr="$1"
	[[ "$(podman inspect -f '{{.State.Running}}' "$ctr" 2>/dev/null)" == true ]]
}

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

run_onbox() {
	local project="$1" command="$2" interactive="$3"
	shift 3
	local -n _read="$1" _write="$2" _ports="$3"
	local ctr
	ctr="$(onbox_container_name "$project")"
	if ! container_exists "$ctr"; then
		if git_mounts_enabled "$project"; then
			volume_exists "$(gitdir_volume "$project" onbox)" || podman volume create "$(gitdir_volume "$project" onbox)" >/dev/null
		fi
		local -a create_args=()
		plan_onbox create_args "$project" "$interactive" "$1" "$2" "$3"
		podman create "${create_args[@]}"
	fi
	podman start "$ctr"
	local -a exec_args=()
	if [[ "$interactive" == yes ]]; then
		exec_args+=("--interactive" "--tty")
	fi
	local status=0
	if [[ -n "$command" ]]; then
		podman exec "${exec_args[@]}" "$ctr" bash -c "$command" || status=$?
	else
		podman exec --interactive --tty "$ctr" /bin/bash || status=$?
	fi
	podman stop -t "$STOP_GRACE_SECONDS" "$ctr" >/dev/null 2>&1 || true
	return "$status"
}

run_recontain() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _ports="$3"
	local -a plan=()
	plan_recontain plan "$project" "$interactive" "$1" "$2" "$3"
	execute_plan "${plan[@]}"
	podman stop -t "$STOP_GRACE_SECONDS" "$(onbox_container_name "$project")" >/dev/null 2>&1 || true
}

run_rebuild() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _ports="$3"
	local -a plan=()
	plan_rebuild plan "$project" "$interactive" "$1" "$2" "$3"
	execute_plan "${plan[@]}"
	podman stop -t "$STOP_GRACE_SECONDS" "$(onbox_container_name "$project")" >/dev/null 2>&1 || true
}

run_rm_container() {
	local project="$1"
	local -a plan=()
	plan_rm_container plan "$project"
	execute_plan "${plan[@]}"
}

run_rm_image() {
	local project="$1"
	local ctr
	ctr="$(onbox_container_name "$project")"
	if image_in_use "$(base_image_name)" "$ctr"; then
		die "cannot remove base image: it is in use by other containers" 1
	fi
	container_exists "$ctr" && podman rm -f --volumes "$ctr"
	local -a plan=()
	plan_rm_image plan "$project" no
	execute_plan "${plan[@]}"
}

source_exists() {
	local source="$1" onbox_e="$2" netbox_e="$3" offbox_e="$4"
	case "$source" in
	onbox) [[ "$onbox_e" == yes ]] ;;
	netbox) [[ "$netbox_e" == yes ]] ;;
	offbox) [[ "$offbox_e" == yes ]] ;;
	*) return 1 ;;
	esac
}

inherit_source() {
	local container="$1" onbox_e="$2" netbox_e="$3" offbox_e="$4" fresh="$5" inherit="$6"
	if [[ "$fresh" == yes ]]; then
		printf '%s\n' base
		return
	fi
	if [[ -n "$inherit" ]]; then
		if source_exists "$inherit" "$onbox_e" "$netbox_e" "$offbox_e"; then
			printf '%s\n' "$inherit"
		else
			printf '%s\n' base
		fi
		return
	fi
	case "$container" in
	netbox)
		if [[ "$onbox_e" == yes ]]; then
			printf '%s\n' onbox
		else
			printf '%s\n' base
		fi
		;;
	offbox)
		if [[ "$netbox_e" == yes ]]; then
			printf '%s\n' netbox
		elif [[ "$onbox_e" == yes ]]; then
			printf '%s\n' onbox
		else
			printf '%s\n' base
		fi
		;;
	esac
}

container_name_of() {
	local source="$1" project="$2"
	case "$source" in
	onbox) printf '%s\n' "$(onbox_container_name "$project")" ;;
	netbox) printf '%s\n' "$(netbox_container_name "$project")" ;;
	offbox) printf '%s\n' "$(offbox_container_name "$project")" ;;
	esac
}

plan_volume_populate() {
	local -n _plan_out="$1"
	local target="$2" source_kind="$3" source="$4"
	_plan_out+=("podman" "run" "--rm" "--network=none" "--userns=keep-id:uid=1000,gid=1000")
	if [[ "$source_kind" == volume ]]; then
		_plan_out+=("-v" "$source:/talkbox/source")
	else
		_plan_out+=("-v" "$source:/talkbox/source:ro")
	fi
	_plan_out+=("-v" "$target:/talkbox/target")
	_plan_out+=("$(base_image_name)")
	_plan_out+=("cp" "-a" "/talkbox/source/." "/talkbox/target/")
}

plan_netbox() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _ports="$6"
	local image="$7"
	local base net port_list
	base="$(project_base "$project")"
	net="pasta"
	if ((${#_ports[@]} > 0)); then
		printf -v port_list '%s,' "${_ports[@]}"
		port_list="${port_list%,}"
		net+=":$port_list"
	fi
	_plan_out+=("--workdir=/working/$base")
	_plan_out+=("--userns=keep-id:uid=1000,gid=1000")
	_plan_out+=("--network=$net")
	_plan_out+=("--cap-drop=NET_ADMIN")
	_plan_out+=("--cap-drop=NET_RAW")
	_plan_out+=("--init")
	if [[ "$TALKBOX_GPU" == yes ]]; then
		_plan_out+=("--device" "nvidia.com/gpu=all")
		_plan_out+=("--group-add" "keep-groups")
	fi
	_plan_out+=("--env" "TALKBOX_PROJECT_SLUG=$(project_slug "$project")")
	_plan_out+=("--env" "TALKBOX_CONTAINER_TYPE=netbox")
	_plan_out+=("-v" "$(netbox_worktree_volume "$project"):/working/$base")
	if git_mounts_enabled "$project"; then
		_plan_out+=("-v" "$(resolve_git_dir "$project"):/host/git:ro")
		_plan_out+=("-v" "$(gitdir_volume "$project" netbox):/working/$base/.git")
		_plan_out+=("-v" "$TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro")
		plan_git_identity_env "${!_plan_out}" "$project"
	fi
	if [[ -d "$TALKBOX_ROOT/defaults/dotfiles" ]]; then
		_plan_out+=("-v" "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro")
	fi
	if [[ -d "$project/.dotfiles" ]]; then
		_plan_out+=("-v" "$project/.dotfiles:/talkbox/dotfiles.project:ro")
	fi
	_plan_out+=("${_read[@]}")
	_plan_out+=("${_write[@]}")
	_plan_out+=("--name=$(netbox_container_name "$project")")
	if [[ "$interactive" == yes ]]; then
		_plan_out+=("--interactive")
		_plan_out+=("--tty")
	fi
	_plan_out+=("$image")
	_plan_out+=("sleep" "infinity")
}

plan_offbox() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _ports="$6"
	local image="$7"
	local base net port_list
	base="$(project_base "$project")"
	net="pasta"
	if ((${#_ports[@]} > 0)); then
		printf -v port_list '%s,' "${_ports[@]}"
		port_list="${port_list%,}"
		net+=":$port_list,-i,lo,-I,talkbox0"
	else
		net+=":-i,lo,-I,talkbox0"
	fi
	_plan_out+=("--workdir=/working/$base")
	_plan_out+=("--userns=keep-id:uid=1000,gid=1000")
	_plan_out+=("--network=$net")
	_plan_out+=("--cap-drop=NET_ADMIN")
	_plan_out+=("--cap-drop=NET_RAW")
	_plan_out+=("--init")
	if [[ "$TALKBOX_GPU" == yes ]]; then
		_plan_out+=("--device" "nvidia.com/gpu=all")
		_plan_out+=("--group-add" "keep-groups")
	fi
	_plan_out+=("--env" "TALKBOX_PROJECT_SLUG=$(project_slug "$project")")
	_plan_out+=("--env" "TALKBOX_CONTAINER_TYPE=offbox")
	_plan_out+=("-v" "$(offbox_worktree_volume "$project"):/working/$base")
	if git_mounts_enabled "$project"; then
		_plan_out+=("-v" "$(resolve_git_dir "$project"):/host/git:ro")
		_plan_out+=("-v" "$(gitdir_volume "$project" offbox):/working/$base/.git")
		_plan_out+=("-v" "$TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro")
		plan_git_identity_env "${!_plan_out}" "$project"
	fi
	if [[ -d "$TALKBOX_ROOT/defaults/dotfiles" ]]; then
		_plan_out+=("-v" "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro")
	fi
	if [[ -d "$project/.dotfiles" ]]; then
		_plan_out+=("-v" "$project/.dotfiles:/talkbox/dotfiles.project:ro")
	fi
	_plan_out+=("${_read[@]}")
	_plan_out+=("${_write[@]}")
	_plan_out+=("--name=$(offbox_container_name "$project")")
	if [[ "$interactive" == yes ]]; then
		_plan_out+=("--interactive")
		_plan_out+=("--tty")
	fi
	_plan_out+=("$image")
	_plan_out+=("sleep" "infinity")
}

plan_netbox_recontain() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _srcs="$6" _dsts="$7" _ports="$8"
	local source="$9"
	local ctr root image
	ctr="$(netbox_container_name "$project")"
	root="$(netbox_root_image "$project")"
	image="$root"
	if [[ "$source" != base ]]; then
		_plan_out+=("podman" "commit" "$(container_name_of "$source" "$project")" "$root")
	else
		image="$(base_image_name)"
	fi
	_plan_out+=("podman" "rm" "-f" "--volumes" "$ctr")
	plan_container_volumes_rm "${!_plan_out}" "$project" netbox "$7"
	plan_netbox_populate "${!_plan_out}" "$project" "$6" "$7"
	plan_gitdir_volume "${!_plan_out}" "$project" netbox
	local -a create_args=()
	plan_netbox create_args "$project" "$interactive" "$4" "$5" "$8" "$image"
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$ctr")
}

plan_offbox_recontain() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _srcs="$6" _dsts="$7" _ports="$8"
	local source="$9"
	local ctr root image
	ctr="$(offbox_container_name "$project")"
	root="$(offbox_root_image "$project")"
	image="$root"
	if [[ "$source" != base ]]; then
		_plan_out+=("podman" "commit" "$(container_name_of "$source" "$project")" "$root")
	else
		image="$(base_image_name)"
	fi
	_plan_out+=("podman" "rm" "-f" "--volumes" "$ctr")
	plan_container_volumes_rm "${!_plan_out}" "$project" offbox "$7"
	plan_offbox_populate "${!_plan_out}" "$project" "$source" "$6" "$7"
	plan_gitdir_volume "${!_plan_out}" "$project" offbox
	local -a create_args=()
	plan_offbox create_args "$project" "$interactive" "$4" "$5" "$8" "$image"
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$ctr")
}

plan_netbox_rebuild() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _srcs="$6" _dsts="$7" _ports="$8"
	local source="$9"
	local ctr root image
	ctr="$(netbox_container_name "$project")"
	root="$(netbox_root_image "$project")"
	image="$root"
	_plan_out+=("podman" "build" "-t" "$(base_image_name)" "-f" "$TALKBOX_ROOT/image/Containerfile" "$TALKBOX_ROOT/image")
	if [[ "$source" != base ]]; then
		_plan_out+=("podman" "commit" "$(container_name_of "$source" "$project")" "$root")
	else
		image="$(base_image_name)"
	fi
	_plan_out+=("podman" "rm" "-f" "--volumes" "$ctr")
	plan_container_volumes_rm "${!_plan_out}" "$project" netbox "$7"
	plan_netbox_populate "${!_plan_out}" "$project" "$6" "$7"
	plan_gitdir_volume "${!_plan_out}" "$project" netbox
	local -a create_args=()
	plan_netbox create_args "$project" "$interactive" "$4" "$5" "$8" "$image"
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$ctr")
}

plan_offbox_rebuild() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _srcs="$6" _dsts="$7" _ports="$8"
	local source="$9"
	local ctr root image
	ctr="$(offbox_container_name "$project")"
	root="$(offbox_root_image "$project")"
	image="$root"
	_plan_out+=("podman" "build" "-t" "$(base_image_name)" "-f" "$TALKBOX_ROOT/image/Containerfile" "$TALKBOX_ROOT/image")
	if [[ "$source" != base ]]; then
		_plan_out+=("podman" "commit" "$(container_name_of "$source" "$project")" "$root")
	else
		image="$(base_image_name)"
	fi
	_plan_out+=("podman" "rm" "-f" "--volumes" "$ctr")
	plan_container_volumes_rm "${!_plan_out}" "$project" offbox "$7"
	plan_offbox_populate "${!_plan_out}" "$project" "$source" "$6" "$7"
	plan_gitdir_volume "${!_plan_out}" "$project" offbox
	local -a create_args=()
	plan_offbox create_args "$project" "$interactive" "$4" "$5" "$8" "$image"
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$ctr")
}

plan_netbox_rm_container() {
	local -n _plan_out="$1"
	local project="$2"
	local -n _dsts="$3"
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(netbox_container_name "$project")")
	plan_container_volumes_rm "${!_plan_out}" "$project" netbox "$3"
	_plan_out+=("podman" "rmi" "$(netbox_root_image "$project")")
}

plan_offbox_rm_container() {
	local -n _plan_out="$1"
	local project="$2"
	local -n _dsts="$3"
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(offbox_container_name "$project")")
	plan_container_volumes_rm "${!_plan_out}" "$project" offbox "$3"
	_plan_out+=("podman" "rmi" "$(offbox_root_image "$project")")
}

plan_netbox_rm_image() {
	plan_rm_image "$@"
}

plan_offbox_rm_image() {
	plan_rm_image "$@"
}

exists_yn() {
	local ctr="$1"
	if container_exists "$ctr"; then
		printf 'yes\n'
	else
		printf 'no\n'
	fi
}

volume_exists() {
	podman volume exists "$1" 2>/dev/null
}

plan_netbox_populate() {
	local -n _plan_out="$1"
	local project="$2"
	local -n _srcs="$3" _dsts="$4"
	local -a vp=()
	plan_volume_populate vp "$(netbox_worktree_volume "$project")" host "$project"
	_plan_out+=("${vp[@]}")
	local i
	for ((i = 0; i < ${#_srcs[@]}; i++)); do
		vp=()
		plan_volume_populate vp "$(netbox_write_volume "$project" "$(dest_slug "${_dsts[$i]}")")" host "${_srcs[$i]}"
		_plan_out+=("${vp[@]}")
	done
}

plan_offbox_populate() {
	local -n _plan_out="$1"
	local project="$2" root_source="$3"
	local -n _srcs="$4" _dsts="$5"
	local -a vp=()
	local netbox_wt netbox_wv
	netbox_wt="$(netbox_worktree_volume "$project")"
	if [[ "$root_source" == netbox ]] && volume_exists "$netbox_wt"; then
		plan_volume_populate vp "$(offbox_worktree_volume "$project")" volume "$netbox_wt"
	else
		plan_volume_populate vp "$(offbox_worktree_volume "$project")" host "$project"
	fi
	_plan_out+=("${vp[@]}")
	local i
	for ((i = 0; i < ${#_srcs[@]}; i++)); do
		vp=()
		netbox_wv="$(netbox_write_volume "$project" "$(dest_slug "${_dsts[$i]}")")"
		if [[ "$root_source" == netbox ]] && volume_exists "$netbox_wv"; then
			plan_volume_populate vp "$(offbox_write_volume "$project" "$(dest_slug "${_dsts[$i]}")")" volume "$netbox_wv"
		else
			plan_volume_populate vp "$(offbox_write_volume "$project" "$(dest_slug "${_dsts[$i]}")")" host "${_srcs[$i]}"
		fi
		_plan_out+=("${vp[@]}")
	done
}

create_netbox() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local source image
	source="$(inherit_source netbox "$(exists_yn "$(onbox_container_name "$project")")" "$(exists_yn "$(netbox_container_name "$project")")" "$(exists_yn "$(offbox_container_name "$project")")" "$TALKBOX_FRESH" "$TALKBOX_INHERIT")"
	if [[ "$source" != base ]]; then
		podman commit "$(container_name_of "$source" "$project")" "$(netbox_root_image "$project")"
		image="$(netbox_root_image "$project")"
	else
		ensure_base_image
		image="$(base_image_name)"
	fi
	local -a plan=()
	plan_netbox_populate plan "$project" "$3" "$4"
	plan_gitdir_volume plan "$project" netbox
	local -a create_args=()
	plan_netbox create_args "$project" "$interactive" "$1" "$2" "$5" "$image"
	plan+=("podman" "create")
	plan+=("${create_args[@]}")
	execute_plan "${plan[@]}"
}

create_offbox() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local source image
	source="$(inherit_source offbox "$(exists_yn "$(onbox_container_name "$project")")" "$(exists_yn "$(netbox_container_name "$project")")" "$(exists_yn "$(offbox_container_name "$project")")" "$TALKBOX_FRESH" "$TALKBOX_INHERIT")"
	if [[ "$source" != base ]]; then
		podman commit "$(container_name_of "$source" "$project")" "$(offbox_root_image "$project")"
		image="$(offbox_root_image "$project")"
	else
		ensure_base_image
		image="$(base_image_name)"
	fi
	local -a plan=()
	plan_offbox_populate plan "$project" "$source" "$3" "$4"
	plan_gitdir_volume plan "$project" offbox
	local -a create_args=()
	plan_offbox create_args "$project" "$interactive" "$1" "$2" "$5" "$image"
	plan+=("podman" "create")
	plan+=("${create_args[@]}")
	execute_plan "${plan[@]}"
}

run_netbox() {
	local project="$1" command="$2" interactive="$3"
	shift 3
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local ctr
	ctr="$(netbox_container_name "$project")"
	if ! container_exists "$ctr"; then
		create_netbox "$project" "$interactive" "$1" "$2" "$3" "$4" "$5"
	fi
	podman start "$ctr"
	local -a exec_args=()
	if [[ "$interactive" == yes ]]; then
		exec_args+=("--interactive" "--tty")
	fi
	local status=0
	if [[ -n "$command" ]]; then
		podman exec "${exec_args[@]}" "$ctr" bash -c "$command" || status=$?
	else
		podman exec --interactive --tty "$ctr" /bin/bash || status=$?
	fi
	podman stop -t "$STOP_GRACE_SECONDS" "$ctr" >/dev/null 2>&1 || true
	return "$status"
}

run_offbox() {
	local project="$1" command="$2" interactive="$3"
	shift 3
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local ctr
	ctr="$(offbox_container_name "$project")"
	if ! container_exists "$ctr"; then
		create_offbox "$project" "$interactive" "$1" "$2" "$3" "$4" "$5"
	fi
	podman start "$ctr"
	local -a exec_args=()
	if [[ "$interactive" == yes ]]; then
		exec_args+=("--interactive" "--tty")
	fi
	local status=0
	if [[ -n "$command" ]]; then
		podman exec "${exec_args[@]}" "$ctr" bash -c "$command" || status=$?
	else
		podman exec --interactive --tty "$ctr" /bin/bash || status=$?
	fi
	podman stop -t "$STOP_GRACE_SECONDS" "$ctr" >/dev/null 2>&1 || true
	return "$status"
}

run_netbox_recontain() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local ctr source
	ctr="$(netbox_container_name "$project")"
	source="$(inherit_source netbox "$(exists_yn "$(onbox_container_name "$project")")" "$(exists_yn "$ctr")" "$(exists_yn "$(offbox_container_name "$project")")" "$TALKBOX_FRESH" "$TALKBOX_INHERIT")"
	if [[ "$source" == base ]]; then
		ensure_base_image
	fi
	local -a plan=()
	plan_netbox_recontain plan "$project" "$interactive" "$1" "$2" "$3" "$4" "$5" "$source"
	execute_plan "${plan[@]}"
	podman stop -t "$STOP_GRACE_SECONDS" "$ctr" >/dev/null 2>&1 || true
}

run_offbox_recontain() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local ctr source
	ctr="$(offbox_container_name "$project")"
	source="$(inherit_source offbox "$(exists_yn "$(onbox_container_name "$project")")" "$(exists_yn "$(netbox_container_name "$project")")" "$(exists_yn "$ctr")" "$TALKBOX_FRESH" "$TALKBOX_INHERIT")"
	if [[ "$source" == base ]]; then
		ensure_base_image
	fi
	local -a plan=()
	plan_offbox_recontain plan "$project" "$interactive" "$1" "$2" "$3" "$4" "$5" "$source"
	execute_plan "${plan[@]}"
	podman stop -t "$STOP_GRACE_SECONDS" "$ctr" >/dev/null 2>&1 || true
}

run_netbox_rebuild() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local ctr source
	ctr="$(netbox_container_name "$project")"
	source="$(inherit_source netbox "$(exists_yn "$(onbox_container_name "$project")")" "$(exists_yn "$ctr")" "$(exists_yn "$(offbox_container_name "$project")")" "$TALKBOX_FRESH" "$TALKBOX_INHERIT")"
	local -a plan=()
	plan_netbox_rebuild plan "$project" "$interactive" "$1" "$2" "$3" "$4" "$5" "$source"
	execute_plan "${plan[@]}"
	podman stop -t "$STOP_GRACE_SECONDS" "$ctr" >/dev/null 2>&1 || true
}

run_offbox_rebuild() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local ctr source
	ctr="$(offbox_container_name "$project")"
	source="$(inherit_source offbox "$(exists_yn "$(onbox_container_name "$project")")" "$(exists_yn "$(netbox_container_name "$project")")" "$(exists_yn "$ctr")" "$TALKBOX_FRESH" "$TALKBOX_INHERIT")"
	local -a plan=()
	plan_offbox_rebuild plan "$project" "$interactive" "$1" "$2" "$3" "$4" "$5" "$source"
	execute_plan "${plan[@]}"
	podman stop -t "$STOP_GRACE_SECONDS" "$ctr" >/dev/null 2>&1 || true
}

run_netbox_rm_container() {
	local project="$1"
	shift
	local ctr root
	ctr="$(netbox_container_name "$project")"
	root="$(netbox_root_image "$project")"
	local -a plan=()
	if podman image exists "$root" >/dev/null 2>&1; then
		plan_netbox_rm_container plan "$project" "$1"
	else
		plan+=("podman" "rm" "-f" "--volumes" "$ctr")
		plan_container_volumes_rm plan "$project" netbox "$1"
	fi
	execute_plan "${plan[@]}"
}

run_offbox_rm_container() {
	local project="$1"
	shift
	local ctr root
	ctr="$(offbox_container_name "$project")"
	root="$(offbox_root_image "$project")"
	local -a plan=()
	if podman image exists "$root" >/dev/null 2>&1; then
		plan_offbox_rm_container plan "$project" "$1"
	else
		plan+=("podman" "rm" "-f" "--volumes" "$ctr")
		plan_container_volumes_rm plan "$project" offbox "$1"
	fi
	execute_plan "${plan[@]}"
}

run_netbox_rm_image() {
	local project="$1"
	local ctr
	ctr="$(netbox_container_name "$project")"
	if image_in_use "$(base_image_name)" "$ctr"; then
		die "cannot remove base image: it is in use by other containers" 1
	fi
	container_exists "$ctr" && podman rm -f --volumes "$ctr"
	local -a plan=()
	plan_netbox_rm_image plan "$project" no
	execute_plan "${plan[@]}"
}

run_offbox_rm_image() {
	local project="$1"
	local ctr
	ctr="$(offbox_container_name "$project")"
	if image_in_use "$(base_image_name)" "$ctr"; then
		die "cannot remove base image: it is in use by other containers" 1
	fi
	container_exists "$ctr" && podman rm -f --volumes "$ctr"
	local -a plan=()
	plan_offbox_rm_image plan "$project" no
	execute_plan "${plan[@]}"
}

container_sync_cmd() {
	local -n _cmd_out="$1"
	local project="$2" container="$3" script="$4"
	shift 4
	local -a branches=("$@")
	local ctr base
	ctr="$(container_name_of "$container" "$project")"
	base="$(project_base "$project")"
	if container_running "$ctr"; then
		_cmd_out+=("podman" "exec" "--workdir=/working/$base" "$ctr" "bash" "-c" "$script" "_")
		_cmd_out+=("${branches[@]}")
	else
		_cmd_out+=("podman" "run" "--rm" "--network=none" "--userns=keep-id:uid=1000,gid=1000" "--workdir=/working/$base" "--entrypoint=/bin/bash")
		_cmd_out+=("-v" "$(gitdir_volume "$project" "$container"):/working/$base/.git")
		case "$container" in
		onbox) _cmd_out+=("-v" "$project:/working/$base") ;;
		netbox) _cmd_out+=("-v" "$(netbox_worktree_volume "$project"):/working/$base") ;;
		offbox) _cmd_out+=("-v" "$(offbox_worktree_volume "$project"):/working/$base") ;;
		esac
		_cmd_out+=("-v" "$(resolve_git_dir "$project"):/host/git:ro")
		_cmd_out+=("-v" "$TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro")
		_cmd_out+=("$(base_image_name)" "-c" "$script" "_")
		_cmd_out+=("${branches[@]}")
	fi
}

run_sync_in_container() {
	local project="$1" container="$2" script="$3"
	shift 3
	local -a cmd=()
	container_sync_cmd cmd "$project" "$container" "$script" "$@"
	"${cmd[@]}"
}
