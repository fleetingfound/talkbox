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

container_name_of() {
	local source="$1" project="$2"
	case "$source" in
	onbox) printf '%s\n' "$(onbox_container_name "$project")" ;;
	netbox) printf '%s\n' "$(netbox_container_name "$project")" ;;
	offbox) printf '%s\n' "$(offbox_container_name "$project")" ;;
	esac
}

root_image_of() {
	local container="$1" project="$2"
	case "$container" in
	netbox) printf '%s\n' "$(netbox_root_image "$project")" ;;
	offbox) printf '%s\n' "$(offbox_root_image "$project")" ;;
	esac
}

worktree_volume_of() {
	local container="$1" project="$2"
	case "$container" in
	onbox) printf '%s\n' "$project" ;;
	netbox) printf '%s\n' "$(netbox_worktree_volume "$project")" ;;
	offbox) printf '%s\n' "$(offbox_worktree_volume "$project")" ;;
	esac
}

write_volume_of() {
	local container="$1" project="$2" dest_slug="$3"
	case "$container" in
	netbox) printf '%s\n' "$(netbox_write_volume "$project" "$dest_slug")" ;;
	offbox) printf '%s\n' "$(offbox_write_volume "$project" "$dest_slug")" ;;
	esac
}

plan_container_volumes_rm() {
	local -n _plan_out="$1"
	local project="$2" container="$3"
	local -n _dsts="$4"
	local i
	if [[ "$container" == onbox ]]; then
		plan_volume_rm "${!_plan_out}" "$(gitdir_volume "$project" "$container")"
		return
	fi
	plan_volume_rm "${!_plan_out}" "$(worktree_volume_of "$container" "$project")"
	plan_volume_rm "${!_plan_out}" "$(gitdir_volume "$project" "$container")"
	for ((i = 0; i < ${#_dsts[@]}; i++)); do
		plan_volume_rm "${!_plan_out}" "$(write_volume_of "$container" "$project" "$(dest_slug "${_dsts[$i]}")")"
	done
}

container_net_suffix() {
	local container="$1"
	case "$container" in
	offbox) printf '%s\n' '-i,lo,-I,talkbox0' ;;
	*) printf '%s\n' '--dns-forward,169.254.1.1,--map-guest-addr,none' ;;
	esac
}

pasta_net() {
	local container="$1"
	local -n _ports="$2"
	local net="pasta:" port_list
	if ((${#_ports[@]} > 0)); then
		printf -v port_list '%s,' "${_ports[@]}"
		net+="$port_list"
	fi
	net+="$(container_net_suffix "$container")"
	printf '%s\n' "$net"
}

plan_container() {
	local -n _plan_out="$1"
	local container="$2" project="$3" interactive="$4"
	shift 4
	local -n _read="$1" _write="$2" _ports="$3"
	local image="$4" base net
	base="$(project_base "$project")"
	net="$(pasta_net "$container" "$3")"
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
	_plan_out+=("--env" "TALKBOX_CONTAINER_TYPE=$container")
	_plan_out+=("-v" "$(worktree_volume_of "$container" "$project"):/working/$base")
	if git_mounts_enabled "$project"; then
		plan_git_mounts "${!_plan_out}" "$project" "$container" hostgit gitdir merge
		plan_git_identity_env "${!_plan_out}" "$project"
	fi
	_plan_out+=("-v" "$TALKBOX_ROOT/image/setup.sh:/usr/local/bin/setup.sh:ro")
	if [[ -d "$TALKBOX_ROOT/defaults/dotfiles" ]]; then
		_plan_out+=("-v" "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro")
	fi
	if [[ -d "$TALKBOX_ROOT/defaults/art" ]]; then
		_plan_out+=("-v" "$TALKBOX_ROOT/defaults/art:/talkbox/art:ro")
	fi
	if [[ -d "$project/.dotfiles" ]]; then
		_plan_out+=("-v" "$project/.dotfiles:/talkbox/dotfiles.project:ro")
	fi
	_plan_out+=("${_read[@]}")
	_plan_out+=("${_write[@]}")
	_plan_out+=("--name=$(container_name_of "$container" "$project")")
	if [[ "$interactive" == yes ]]; then
		_plan_out+=("--interactive")
		_plan_out+=("--tty")
	fi
	_plan_out+=("$image")
	_plan_out+=("sleep" "infinity")
}

plan_volume_populate() {
	local -n _plan_out="$1"
	local target="$2" source_kind="$3" source="$4"
	plan_no_net_run "${!_plan_out}"
	if [[ "$source_kind" == volume ]]; then
		_plan_out+=("-v" "$source:/talkbox/source")
	else
		_plan_out+=("-v" "$source:/talkbox/source:ro")
	fi
	_plan_out+=("-v" "$target:/talkbox/target")
	_plan_out+=("$(base_image_name)")
	_plan_out+=("cp" "-a" "/talkbox/source/." "/talkbox/target/")
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

plan_recreate() {
	local -n _plan_out="$1"
	local container="$2" rebuild="$3" interactive="$4" project="$5"
	shift 5
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local source="$6"
	local ctr image
	ctr="$(container_name_of "$container" "$project")"
	image="$(base_image_name)"
	if [[ "$rebuild" == yes ]]; then
		_plan_out+=("podman" "build" "-t" "$(base_image_name)" "-f" "$TALKBOX_ROOT/image/Containerfile" "$TALKBOX_ROOT/image")
	fi
	if [[ "$container" != onbox && "$source" != base ]]; then
		image="$(root_image_of "$container" "$project")"
		_plan_out+=("podman" "commit" "$(container_name_of "$source" "$project")" "$image")
	fi
	_plan_out+=("podman" "rm" "-f" "--volumes" "$ctr")
	plan_container_volumes_rm "${!_plan_out}" "$project" "$container" "$4"
	case "$container" in
	netbox) plan_netbox_populate "${!_plan_out}" "$project" "$3" "$4" ;;
	offbox) plan_offbox_populate "${!_plan_out}" "$project" "$source" "$3" "$4" ;;
	esac
	plan_gitdir_volume "${!_plan_out}" "$project" "$container"
	local -a create_args=()
	plan_container create_args "$container" "$project" "$interactive" "$1" "$2" "$5" "$image"
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$ctr")
}

plan_rm_container() {
	local -n _plan_out="$1"
	local container="$2" project="$3"
	shift 3
	local -n _dsts="$1"
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(container_name_of "$container" "$project")")
	plan_container_volumes_rm "${!_plan_out}" "$project" "$container" "$1"
	if [[ "$container" != onbox ]] && podman image exists "$(root_image_of "$container" "$project")" >/dev/null 2>&1; then
		_plan_out+=("podman" "rmi" "$(root_image_of "$container" "$project")")
	fi
}

plan_rm_image() {
	local -n _plan_out="$1"
	_plan_out+=("podman" "rmi" "$(base_image_name)")
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

prune_external_image_containers() {
	local image="$1" id
	local ids
	ids="$(podman ps -a --external --filter "ancestor=$image" --format '{{.ID}}')"
	for id in $ids; do
		podman rm -f "$id"
	done
}

stop_container() {
	podman stop -t "$STOP_GRACE_SECONDS" "$1" >/dev/null 2>&1 || true
}

install_nft_deny_or_die() {
	local ctr="$1"
	if ! install_nft_deny "$@"; then
		stop_container "$ctr"
		die "cannot apply nftables deny/allow rules in container $ctr; deny list left unenforced" 1
	fi
}

run_setup_in_container() {
	local ctr="$1"
	if ! podman exec "$ctr" setup.sh; then
		stop_container "$ctr"
		die "cannot run setup.sh in container $ctr; setup failed" 1
	fi
}

exec_in_container() {
	local ctr="$1" command="$2" interactive="$3"
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
	stop_container "$ctr"
	return "$status"
}

inherit_source_for() {
	local container="$1" project="$2"
	inherit_source "$container" "$(exists_yn "$(onbox_container_name "$project")")" "$(exists_yn "$(netbox_container_name "$project")")" "$(exists_yn "$(offbox_container_name "$project")")" "$TALKBOX_FRESH" "$TALKBOX_INHERIT"
}

create_sandbox() {
	local container="$1" project="$2" interactive="$3"
	shift 3
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local source image
	image="$(base_image_name)"
	if [[ "$container" == onbox ]]; then
		source=base
	else
		source="$(inherit_source_for "$container" "$project")"
		if [[ "$source" != base ]]; then
			image="$(root_image_of "$container" "$project")"
		else
			ensure_base_image
		fi
	fi
	local -a plan=()
	if [[ "$source" != base ]]; then
		plan+=("podman" "commit" "$(container_name_of "$source" "$project")" "$image")
	fi
	case "$container" in
	netbox) plan_netbox_populate plan "$project" "$3" "$4" ;;
	offbox) plan_offbox_populate plan "$project" "$source" "$3" "$4" ;;
	esac
	plan_gitdir_volume plan "$project" "$container"
	local -a create_args=()
	plan_container create_args "$container" "$project" "$interactive" "$1" "$2" "$5" "$image"
	plan+=("podman" "create")
	plan+=("${create_args[@]}")
	execute_plan "${plan[@]}"
}

run_container() {
	local container="$1" project="$2" command="$3" interactive="$4"
	shift 4
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5" _deny="$6" _allow="$7"
	local ctr
	ctr="$(container_name_of "$container" "$project")"
	if ! container_exists "$ctr"; then
		create_sandbox "$container" "$project" "$interactive" "$1" "$2" "$3" "$4" "$5"
	fi
	podman start "$ctr"
	if [[ "$container" != offbox ]]; then
		install_nft_deny_or_die "$ctr" "$6" "$7"
	fi
	run_setup_in_container "$ctr"
	exec_in_container "$ctr" "$command" "$interactive"
}

run_recreate() {
	local container="$1" rebuild="$2" project="$3" interactive="$4"
	shift 4
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5" _deny="$6" _allow="$7"
	local ctr source
	ctr="$(container_name_of "$container" "$project")"
	if [[ "$container" == onbox ]]; then
		source=base
	else
		source="$(inherit_source_for "$container" "$project")"
		if [[ "$rebuild" != yes && "$source" == base ]]; then
			ensure_base_image
		fi
	fi
	local -a plan=()
	plan_recreate plan "$container" "$rebuild" "$interactive" "$project" "$1" "$2" "$3" "$4" "$5" "$source"
	execute_plan "${plan[@]}"
	if [[ "$container" != onbox ]]; then
		if [[ "$container" != offbox ]]; then
			install_nft_deny_or_die "$ctr" "$6" "$7"
		fi
		run_setup_in_container "$ctr"
	fi
	stop_container "$ctr"
}

run_rm_container_any() {
	local container="$1" project="$2"
	shift 2
	local -n _dsts="$1"
	local -a plan=()
	plan_rm_container plan "$container" "$project" "$1"
	execute_plan "${plan[@]}"
}

run_rm_image_any() {
	local container="$1" project="$2"
	local ctr
	ctr="$(container_name_of "$container" "$project")"
	if image_in_use "$(base_image_name)" "$ctr"; then
		die "cannot remove base image: it is in use by other containers" 1
	fi
	container_exists "$ctr" && podman rm -f --volumes "$ctr"
	prune_external_image_containers "$(base_image_name)"
	local -a plan=()
	plan_rm_image plan
	execute_plan "${plan[@]}"
}

run_onbox() {
	# shellcheck disable=SC2034 # dummy arrays are consumed by nameref parameters
	local -a no_mounts=()
	run_container onbox "$1" "$2" "$3" "$4" "$5" no_mounts no_mounts "$6" "$7" "$8"
}

run_netbox() {
	run_container netbox "$@"
}

run_offbox() {
	run_container offbox "$@"
}

run_recontain() {
	local -a no_mounts=()
	run_recreate onbox no "$1" "$2" "$3" "$4" no_mounts no_mounts "$5" "$6" "$7"
}

run_onbox_recontain() {
	run_recontain "$@"
}

run_rebuild() {
	# shellcheck disable=SC2034 # dummy arrays are consumed by nameref parameters
	local -a no_mounts=()
	run_recreate onbox yes "$1" "$2" "$3" "$4" no_mounts no_mounts "$5" "$6" "$7"
}

run_onbox_rebuild() {
	run_rebuild "$@"
}

run_netbox_recontain() {
	run_recreate netbox no "$@"
}

run_offbox_recontain() {
	run_recreate offbox no "$@"
}

run_netbox_rebuild() {
	run_recreate netbox yes "$@"
}

run_offbox_rebuild() {
	run_recreate offbox yes "$@"
}

run_rm_container() {
	# shellcheck disable=SC2034 # dummy array is consumed by nameref parameter
	local -a no_dsts=()
	run_rm_container_any onbox "$1" no_dsts
}

run_onbox_rm_container() {
	run_rm_container "$1"
}

run_netbox_rm_container() {
	run_rm_container_any netbox "$1" "$2"
}

run_offbox_rm_container() {
	run_rm_container_any offbox "$1" "$2"
}

run_rm_image() {
	run_rm_image_any onbox "$1"
}

run_onbox_rm_image() {
	run_rm_image "$@"
}

run_netbox_rm_image() {
	run_rm_image_any netbox "$1"
}

run_offbox_rm_image() {
	run_rm_image_any offbox "$1"
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
		plan_no_net_run "${!_cmd_out}"
		_cmd_out+=("--workdir=/working/$base")
		plan_git_mounts "${!_cmd_out}" "$project" "$container" gitdir
		_cmd_out+=("-v" "$(worktree_volume_of "$container" "$project"):/working/$base")
		plan_git_mounts "${!_cmd_out}" "$project" "$container" hostgit merge
		# shellcheck disable=SC2016 # $0 and $@ expand inside the container at run time
		_cmd_out+=("$(base_image_name)" "bash" "-c" 'setup.sh && exec bash -c "$0" _ "$@"' "$script")
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
