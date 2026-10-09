# shellcheck shell=bash
# shellcheck disable=SC2178 # _plan_out is a nameref to a caller-declared array

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/definitions.sh"
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
	local container="$1" project="$2"
	printf '%s\n' "$(project_slug "$project").$container"
}

root_image_of() {
	local container="$1" project="$2"
	printf '%s\n' "$(project_slug "$project").$container.root"
}

worktree_volume_of() {
	local container="$1" project="$2"
	if [[ "$container" == onbox ]]; then
		printf '%s\n' "$project"
	else
		printf '%s\n' "$(project_slug "$project").$container.worktree"
	fi
}

write_volume_of() {
	local container="$1" project="$2" dest_slug="$3"
	printf '%s\n' "$(project_slug "$project").$container.write.$dest_slug"
}

container_volumes() {
	local -n _vols="$1"
	local container="$2" project="$3"
	local -n _dsts="$4"
	_vols=()
	if [[ "$(container_config named_worktree_volume "$container")" == yes ]]; then
		_vols+=("$(worktree_volume_of "$container" "$project")")
	fi
	_vols+=("$(gitdir_volume "$project" "$container")")
	local i
	for ((i = 0; i < ${#_dsts[@]}; i++)); do
		_vols+=("$(write_volume_of "$container" "$project" "$(dest_slug "${_dsts[$i]}")")")
	done
}

container_write_volumes() {
	local -n _vols="$1"
	local container="$2" project="$3"
	local ctr prefix mounts name
	_vols=()
	ctr="$(container_name_of "$container" "$project")"
	if ! container_exists "$ctr"; then
		return 0
	fi
	prefix="$(project_slug "$project").$container.write."
	mounts="$(podman inspect -f '{{range .Mounts}}{{.Name}} {{end}}' "$ctr" 2>/dev/null || true)"
	for name in $mounts; do
		if [[ "$name" == "$prefix"* ]]; then
			_vols+=("$name")
		fi
	done
}

plan_container_volumes_rm() {
	local -n _plan_out="$1"
	local project="$2" container="$3"
	if [[ "$(container_config named_worktree_volume "$container")" == yes ]]; then
		plan_volume_rm "${!_plan_out}" "$(worktree_volume_of "$container" "$project")"
	fi
	plan_volume_rm "${!_plan_out}" "$(gitdir_volume "$project" "$container")"
	local -a vols=()
	container_write_volumes vols "$container" "$project"
	local v
	for v in "${vols[@]}"; do
		plan_volume_rm "${!_plan_out}" "$v"
	done
}

pasta_net() {
	local container="$1"
	local -n _ports="$2"
	local net="pasta:" port_list
	if ((${#_ports[@]} > 0)); then
		printf -v port_list '%s,' "${_ports[@]}"
		net+="$port_list"
	fi
	net+="$(container_config pasta_suffix "$container")"
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

plan_volume_populate_from() {
	local -n _plan_out="$1"
	local target="$2" source_volume="$3" host_source="$4"
	if [[ -n "$source_volume" ]] && volume_exists "$source_volume"; then
		plan_volume_populate "${!_plan_out}" "$target" volume "$source_volume"
	else
		plan_volume_populate "${!_plan_out}" "$target" host "$host_source"
	fi
}

plan_container_populate() {
	local -n _plan_out="$1"
	local container="$2" project="$3" source="$4"
	local -n _srcs="$5" _dsts="$6"
	local policy
	policy="$(container_config populate_policy "$container")"
	if [[ "$policy" == none ]]; then
		return 0
	fi
	local from_source=no
	if [[ "$policy" == source-else-host && "$(container_config write_style "$source")" == volume ]]; then
		from_source=yes
	fi
	local -a vp=()
	local i source_volume
	source_volume=""
	if [[ "$from_source" == yes ]]; then
		source_volume="$(worktree_volume_of "$source" "$project")"
	fi
	plan_volume_populate_from vp "$(worktree_volume_of "$container" "$project")" "$source_volume" "$project"
	_plan_out+=("${vp[@]}")
	for ((i = 0; i < ${#_srcs[@]}; i++)); do
		vp=()
		source_volume=""
		if [[ "$from_source" == yes ]]; then
			source_volume="$(write_volume_of "$source" "$project" "$(dest_slug "${_dsts[$i]}")")"
		fi
		plan_volume_populate_from vp "$(write_volume_of "$container" "$project" "$(dest_slug "${_dsts[$i]}")")" "$source_volume" "${_srcs[$i]}"
		_plan_out+=("${vp[@]}")
	done
}

plan_populate_and_create() {
	local -n _plan_out="$1"
	local container="$2" interactive="$3" project="$4" source="$5" image="$6"
	shift 6
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	plan_container_populate "${!_plan_out}" "$container" "$project" "$source" "$3" "$4"
	plan_gitdir_volume "${!_plan_out}" "$project" "$container"
	local -a create_args=()
	plan_container create_args "$container" "$project" "$interactive" "$1" "$2" "$5" "$image"
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
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
	if [[ "$(container_config root_image "$container")" == yes && "$source" != base ]]; then
		image="$(root_image_of "$container" "$project")"
		_plan_out+=("podman" "commit" "$(container_name_of "$source" "$project")" "$image")
	fi
	_plan_out+=("podman" "rm" "-f" "--volumes" "$ctr")
	plan_container_volumes_rm "${!_plan_out}" "$project" "$container"
	plan_populate_and_create "${!_plan_out}" "$container" "$interactive" "$project" "$source" "$image" "$1" "$2" "$3" "$4" "$5"
	_plan_out+=("podman" "start" "$ctr")
}

plan_rm_container() {
	local -n _plan_out="$1"
	local container="$2" project="$3"
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(container_name_of "$container" "$project")")
	plan_container_volumes_rm "${!_plan_out}" "$project" "$container"
	if [[ "$(container_config root_image "$container")" == yes ]] && podman image exists "$(root_image_of "$container" "$project")" >/dev/null 2>&1; then
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
			"${cmd[@]}" || return $?
			cmd=()
		fi
		cmd+=("$arg")
	done
	if ((${#cmd[@]} > 0)); then
		"${cmd[@]}" || return $?
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
	local parent
	for parent in $(container_config default_parents "$container"); do
		if source_exists "$parent" "$onbox_e" "$netbox_e" "$offbox_e"; then
			printf '%s\n' "$parent"
			return
		fi
	done
	printf '%s\n' base
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

stop_and_die() {
	local ctr="$1" message="$2"
	stop_container "$ctr"
	die "$message" 1
}

rollback_creation_and_die() {
	local container="$1" project="$2"
	local -n _dsts="$3"
	local ctr v
	ctr="$(container_name_of "$container" "$project")"
	stop_container "$ctr"
	podman rm -f "$ctr" || true
	local -a vols=()
	container_volumes vols "$container" "$project" "$3"
	for v in "${vols[@]}"; do
		if volume_exists "$v"; then
			podman volume rm -f "$v" || true
		fi
	done
	die "cannot create container $ctr; rolled back the partial container and volumes" 1
}

install_nft_deny_or_die() {
	local ctr="$1"
	if ! install_nft_deny "$@"; then
		stop_and_die "$ctr" "cannot apply nftables deny/allow rules in container $ctr; deny list left unenforced"
	fi
}

run_setup_in_container() {
	local ctr="$1"
	if ! podman exec "$ctr" setup.sh; then
		stop_and_die "$ctr" "cannot run setup.sh in container $ctr; setup failed"
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
	inherit_source "$container" "$(exists_yn "$(container_name_of onbox "$project")")" "$(exists_yn "$(container_name_of netbox "$project")")" "$(exists_yn "$(container_name_of offbox "$project")")" "$TALKBOX_FRESH" "$TALKBOX_INHERIT"
}

resolve_inheritance() {
	local container="$1" rebuild="$2" project="$3"
	local -n _source_out="$4"
	local -n _image_out="$5"
	_image_out="$(base_image_name)"
	_source_out=base
	if [[ "$(container_config root_image "$container")" == yes ]]; then
		_source_out="$(inherit_source_for "$container" "$project")"
		if [[ "$_source_out" != base ]]; then
			_image_out="$(root_image_of "$container" "$project")"
		fi
	fi
	if [[ "$_source_out" == base && "$rebuild" != yes ]]; then
		ensure_base_image
	fi
}

create_sandbox() {
	local container="$1" project="$2" interactive="$3"
	shift 3
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5"
	local source image
	resolve_inheritance "$container" no "$project" source image
	local -a plan=()
	if [[ "$source" != base ]]; then
		plan+=("podman" "commit" "$(container_name_of "$source" "$project")" "$image")
	fi
	plan_populate_and_create plan "$container" "$interactive" "$project" "$source" "$image" "$1" "$2" "$3" "$4" "$5"
	if ! execute_plan "${plan[@]}"; then
		rollback_creation_and_die "$container" "$project" "$4"
	fi
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
	if [[ "$(container_config nft_enforce "$container")" == yes ]]; then
		install_nft_deny_or_die "$ctr" "$6" "$7"
	fi
	run_setup_in_container "$ctr"
	exec_in_container "$ctr" "$command" "$interactive"
}

run_recreate() {
	local container="$1" rebuild="$2" project="$3" interactive="$4"
	shift 4
	local -n _read="$1" _write="$2" _srcs="$3" _dsts="$4" _ports="$5" _deny="$6" _allow="$7"
	local ctr source image
	ctr="$(container_name_of "$container" "$project")"
	resolve_inheritance "$container" "$rebuild" "$project" source image
	local -a plan=()
	plan_recreate plan "$container" "$rebuild" "$interactive" "$project" "$1" "$2" "$3" "$4" "$5" "$source"
	if ! execute_plan "${plan[@]}"; then
		rollback_creation_and_die "$container" "$project" "$4"
	fi
	if [[ "$(container_config nft_enforce "$container")" == yes ]]; then
		install_nft_deny_or_die "$ctr" "$6" "$7"
	fi
	run_setup_in_container "$ctr"
	stop_container "$ctr"
}

run_rm_container() {
	local container="$1" project="$2"
	local -a plan=()
	plan_rm_container plan "$container" "$project"
	execute_plan "${plan[@]}"
}

run_rm_image() {
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
