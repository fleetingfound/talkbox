#!/usr/bin/env bash
set -euo pipefail

TALKBOX_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export TALKBOX_ROOT

source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"
source "$TALKBOX_ROOT/lib/options.sh"
source "$TALKBOX_ROOT/lib/mounts.sh"
source "$TALKBOX_ROOT/lib/network.sh"
source "$TALKBOX_ROOT/lib/git.sh"
source "$TALKBOX_ROOT/lib/containers.sh"

container_action() {
	local container="$1"
	shift
	parse_talkbox_options "$@"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local read_mounts=() write_mounts=() ports=() write_srcs=() write_dsts=() deny_ips=() allow_ips=()
	mount_args read_mounts read "$TALKBOX_ROOT/defaults/read.mounts" "$(pwd)" "$HOME" "${TALKBOX_READ[@]}"
	if [[ "$container" == onbox ]]; then
		mount_args write_mounts write "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${TALKBOX_WRITE[@]}"
	else
		mount_entries write_srcs write_dsts write "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${TALKBOX_WRITE[@]}"
		mount_volume_args write_mounts "$container" "$(pwd)" write_srcs write_dsts
	fi
	port_args ports "$TALKBOX_ROOT/defaults/ports" "${TALKBOX_PORT[@]}"
	if [[ "$container" != offbox ]]; then
		deny_allow_args deny_ips allow_ips "$TALKBOX_ROOT/defaults/deny.ip" "$TALKBOX_ROOT/defaults/allow.ip" TALKBOX_DENY_IP TALKBOX_ALLOW_IP
	fi
	local -a write_entries=()
	if [[ "$container" != onbox ]]; then
		write_entries=(write_srcs write_dsts)
	fi
	case "$TALKBOX_VERB" in
	fetch)
		run_fetch "$(pwd)" "$container" "$TALKBOX_ALL"
		;;
	merge)
		run_merge "$(pwd)" "$container" "$TALKBOX_ALL" "$TALKBOX_BRANCH"
		;;
	sync)
		run_sync "$(pwd)" "$container" "$TALKBOX_ALL" "$TALKBOX_BRANCH"
		;;
	recontain)
		prepare_git_host "$(pwd)"
		"run_${container}_recontain" "$(pwd)" "$TALKBOX_INTERACTIVE" read_mounts write_mounts "${write_entries[@]}" ports deny_ips allow_ips
		;;
	rebuild)
		prepare_git_host "$(pwd)"
		"run_${container}_rebuild" "$(pwd)" "$TALKBOX_INTERACTIVE" read_mounts write_mounts "${write_entries[@]}" ports deny_ips allow_ips
		;;
	rm-container)
		"run_${container}_rm_container" "$(pwd)" write_dsts
		;;
	rm-image)
		"run_${container}_rm_image" "$(pwd)"
		;;
	*)
		prepare_git_host "$(pwd)"
		"run_${container}" "$(pwd)" "$TALKBOX_COMMAND" "$TALKBOX_INTERACTIVE" read_mounts write_mounts "${write_entries[@]}" ports deny_ips allow_ips
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
onbox | netbox | offbox)
	container_action "$container" "$@"
	;;
*)
	die "unknown container: $container" 2
	;;
esac
