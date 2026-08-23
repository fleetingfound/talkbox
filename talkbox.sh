#!/usr/bin/env bash
set -euo pipefail

TALKBOX_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export TALKBOX_ROOT

source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"
source "$TALKBOX_ROOT/lib/options.sh"
source "$TALKBOX_ROOT/lib/mounts.sh"
source "$TALKBOX_ROOT/lib/ports.sh"
source "$TALKBOX_ROOT/lib/git.sh"
source "$TALKBOX_ROOT/lib/containers.sh"

onbox_action() {
	parse_onbox_options "$@"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local read_mounts=() write_mounts=() ports=()
	mount_args read_mounts read "$TALKBOX_ROOT/defaults/read.mounts" "$(pwd)" "$HOME" "${ONBOX_READ[@]}"
	mount_args write_mounts write "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${ONBOX_WRITE[@]}"
	port_args ports "$TALKBOX_ROOT/defaults/ports" "${ONBOX_PORT[@]}"
	case "$ONBOX_VERB" in
	fetch)
		run_fetch "$(pwd)" onbox "$ONBOX_ALL"
		;;
	recontain)
		prepare_git_host "$(pwd)"
		ensure_base_image
		run_recontain "$(pwd)" "$ONBOX_INTERACTIVE" read_mounts write_mounts ports
		;;
	rebuild)
		prepare_git_host "$(pwd)"
		run_rebuild "$(pwd)" "$ONBOX_INTERACTIVE" read_mounts write_mounts ports
		;;
	rm-container)
		run_rm_container "$(pwd)"
		;;
	rm-image)
		run_rm_image "$(pwd)"
		;;
	*)
		prepare_git_host "$(pwd)"
		ensure_base_image
		run_onbox "$(pwd)" "$ONBOX_COMMAND" "$ONBOX_INTERACTIVE" read_mounts write_mounts ports
		;;
	esac
}

sandbox_action() {
	local container="$1"
	shift
	parse_onbox_options "$@"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local read_mounts=() write_mounts=() ports=() write_srcs=() write_dsts=()
	mount_args read_mounts read "$TALKBOX_ROOT/defaults/read.mounts" "$(pwd)" "$HOME" "${ONBOX_READ[@]}"
	mount_entries write_srcs write_dsts write "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${ONBOX_WRITE[@]}"
	mount_volume_args write_mounts "$container" "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${ONBOX_WRITE[@]}"
	port_args ports "$TALKBOX_ROOT/defaults/ports" "${ONBOX_PORT[@]}"
	case "$ONBOX_VERB" in
	fetch)
		run_fetch "$(pwd)" "$container" "$ONBOX_ALL"
		;;
	recontain)
		prepare_git_host "$(pwd)"
		"run_${container}_recontain" "$(pwd)" "$ONBOX_INTERACTIVE" read_mounts write_mounts write_srcs write_dsts ports
		;;
	rebuild)
		prepare_git_host "$(pwd)"
		"run_${container}_rebuild" "$(pwd)" "$ONBOX_INTERACTIVE" read_mounts write_mounts write_srcs write_dsts ports
		;;
	rm-container)
		"run_${container}_rm_container" "$(pwd)"
		;;
	rm-image)
		"run_${container}_rm_image" "$(pwd)"
		;;
	*)
		prepare_git_host "$(pwd)"
		"run_${container}" "$(pwd)" "$ONBOX_COMMAND" "$ONBOX_INTERACTIVE" read_mounts write_mounts write_srcs write_dsts ports
		;;
	esac
}

invoked="$(basename "$0")"
if [[ "$invoked" == "talkbox.sh" ]]; then
	if [[ $# -eq 0 ]]; then
		die 'usage: talkbox.sh <onbox|netbox|offbox> ...' 2
	fi
	container="$1"
	shift
else
	container="$invoked"
fi

case "$container" in
onbox)
	onbox_action "$@"
	;;
netbox)
	sandbox_action netbox "$@"
	;;
offbox)
	sandbox_action offbox "$@"
	;;
*)
	die "unknown container: $container" 2
	;;
esac
