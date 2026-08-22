# shellcheck shell=bash

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/naming.sh"

plan_onbox() {
	local -n _plan_out="$1"
	local project="$2" command="$3" interactive="$4" rm="$5"
	local base
	base="$(project_base "$project")"
	_plan_out+=("--workdir=/working/$base")
	_plan_out+=("--userns=keep-id:uid=1000,gid=1000")
	_plan_out+=("--network=pasta")
	_plan_out+=("--cap-drop=NET_ADMIN")
	_plan_out+=("--cap-drop=NET_RAW")
	_plan_out+=("-v" "$project:/working/$base")
	if [[ -d "$TALKBOX_ROOT/defaults/dotfiles" ]]; then
		_plan_out+=("-v" "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro")
	fi
	if [[ -d "$project/.dotfiles" ]]; then
		_plan_out+=("-v" "$project/.dotfiles:/talkbox/dotfiles.project:ro")
	fi
	if [[ "$rm" == yes ]]; then
		_plan_out+=("--rm")
	fi
	if [[ "$interactive" == yes ]]; then
		_plan_out+=("--interactive")
		_plan_out+=("--tty")
	fi
	_plan_out+=("$(base_image_name)")
	if [[ -n "$command" ]]; then
		_plan_out+=("$command")
	fi
}

ensure_base_image() {
	if ! podman image exists "$(base_image_name)" >/dev/null 2>&1; then
		podman build -t "$(base_image_name)" -f "$TALKBOX_ROOT/image/Containerfile" "$TALKBOX_ROOT/image"
	fi
}

run_onbox() {
	local project="$1" command="$2" interactive="$3"
	local args=()
	plan_onbox args "$project" "$command" "$interactive" yes
	podman run "${args[@]}"
}
