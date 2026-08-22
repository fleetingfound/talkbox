#!/usr/bin/env bash
set -euo pipefail

TALKBOX_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export TALKBOX_ROOT

source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"
source "$TALKBOX_ROOT/lib/options.sh"
source "$TALKBOX_ROOT/lib/mounts.sh"
source "$TALKBOX_ROOT/lib/ports.sh"
source "$TALKBOX_ROOT/lib/containers.sh"

onbox_action() {
	parse_onbox_options "$@"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local read_mounts=() write_mounts=() ports=()
	mount_args read_mounts read "$TALKBOX_ROOT/defaults/read.mounts" "$(pwd)" "$HOME" "${ONBOX_READ[@]}"
	mount_args write_mounts write "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${ONBOX_WRITE[@]}"
	port_args ports "$TALKBOX_ROOT/defaults/ports" "${ONBOX_PORT[@]}"
	case "$ONBOX_VERB" in
	recontain)
		ensure_base_image
		run_recontain "$(pwd)" "$ONBOX_INTERACTIVE" read_mounts write_mounts ports
		;;
	rebuild)
		run_rebuild "$(pwd)" "$ONBOX_INTERACTIVE" read_mounts write_mounts ports
		;;
	rm-container)
		run_rm_container "$(pwd)"
		;;
	rm-image)
		run_rm_image "$(pwd)"
		;;
	*)
		ensure_base_image
		run_onbox "$(pwd)" "$ONBOX_COMMAND" "$ONBOX_INTERACTIVE" read_mounts write_mounts ports
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
netbox | offbox)
	die "$container is not implemented yet" 1
	;;
*)
	die "unknown container: $container" 2
	;;
esac
