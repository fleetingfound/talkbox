# shellcheck shell=bash
# shellcheck disable=SC2178 # _plan_out is a nameref to a caller-declared array

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"

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
	_plan_out+=("-v" "$project:/working/$base")
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

plan_onbox_run() {
	local -n _plan_out="$1"
	local project="$2" command="$3" interactive="$4"
	local -n _read="$5" _write="$6" _ports="$7"
	local -a create_args=()
	plan_onbox create_args "$project" "$interactive" "$5" "$6" "$7"
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$(onbox_container_name "$project")")
	if [[ -n "$command" ]]; then
		_plan_out+=("podman" "exec")
		if [[ "$interactive" == yes ]]; then
			_plan_out+=("--interactive")
			_plan_out+=("--tty")
		fi
		_plan_out+=("$(onbox_container_name "$project")" "bash" "-c" "$command")
	fi
}

plan_recontain() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _ports="$6"
	local -a create_args=()
	plan_onbox create_args "$project" "$interactive" "$4" "$5" "$6"
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(onbox_container_name "$project")")
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$(onbox_container_name "$project")")
}

plan_rebuild() {
	local -n _plan_out="$1"
	local project="$2" interactive="$3"
	local -n _read="$4" _write="$5" _ports="$6"
	local -a create_args=()
	plan_onbox create_args "$project" "$interactive" "$4" "$5" "$6"
	_plan_out+=("podman" "build" "-t" "$(base_image_name)" "-f" "$TALKBOX_ROOT/image/Containerfile" "$TALKBOX_ROOT/image")
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(onbox_container_name "$project")")
	_plan_out+=("podman" "create")
	_plan_out+=("${create_args[@]}")
	_plan_out+=("podman" "start" "$(onbox_container_name "$project")")
}

plan_rm_container() {
	local -n _plan_out="$1"
	local project="$2"
	_plan_out+=("podman" "rm" "-f" "--volumes" "$(onbox_container_name "$project")")
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
	podman stop -t 1 "$ctr" >/dev/null 2>&1 || true
	return "$status"
}

run_recontain() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _ports="$3"
	local -a plan=()
	plan_recontain plan "$project" "$interactive" "$1" "$2" "$3"
	execute_plan "${plan[@]}"
	podman stop -t 1 "$(onbox_container_name "$project")" >/dev/null 2>&1 || true
}

run_rebuild() {
	local project="$1" interactive="$2"
	shift 2
	local -n _read="$1" _write="$2" _ports="$3"
	local -a plan=()
	plan_rebuild plan "$project" "$interactive" "$1" "$2" "$3"
	execute_plan "${plan[@]}"
	podman stop -t 1 "$(onbox_container_name "$project")" >/dev/null 2>&1 || true
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
