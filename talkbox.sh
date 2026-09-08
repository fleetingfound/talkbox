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

onbox_action() {
	parse_talkbox_options "$@"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local read_mounts=() write_mounts=() ports=() deny_ips=() allow_ips=()
	mount_args read_mounts read "$TALKBOX_ROOT/defaults/read.mounts" "$(pwd)" "$HOME" "${TALKBOX_READ[@]}"
	mount_args write_mounts write "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${TALKBOX_WRITE[@]}"
	port_args ports "$TALKBOX_ROOT/defaults/ports" "${TALKBOX_PORT[@]}"
	deny_allow_args deny_ips allow_ips "$TALKBOX_ROOT/defaults/deny.ip" "$TALKBOX_ROOT/defaults/allow.ip" TALKBOX_DENY_IP TALKBOX_ALLOW_IP
	case "$TALKBOX_VERB" in
	fetch)
		run_fetch "$(pwd)" onbox "$TALKBOX_ALL"
		;;
	merge)
		run_merge "$(pwd)" onbox "$TALKBOX_ALL" "$TALKBOX_BRANCH"
		;;
	sync)
		run_sync "$(pwd)" onbox "$TALKBOX_ALL" "$TALKBOX_BRANCH"
		;;
	recontain)
		prepare_git_host "$(pwd)"
		ensure_base_image
		run_recontain "$(pwd)" "$TALKBOX_INTERACTIVE" read_mounts write_mounts ports deny_ips allow_ips
		;;
	rebuild)
		prepare_git_host "$(pwd)"
		run_rebuild "$(pwd)" "$TALKBOX_INTERACTIVE" read_mounts write_mounts ports deny_ips allow_ips
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
		run_onbox "$(pwd)" "$TALKBOX_COMMAND" "$TALKBOX_INTERACTIVE" read_mounts write_mounts ports deny_ips allow_ips
		;;
	esac
}

sandbox_action() {
	local container="$1"
	shift
	parse_talkbox_options "$@"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local read_mounts=() write_mounts=() ports=() write_srcs=() write_dsts=() deny_ips=() allow_ips=()
	mount_args read_mounts read "$TALKBOX_ROOT/defaults/read.mounts" "$(pwd)" "$HOME" "${TALKBOX_READ[@]}"
	mount_entries write_srcs write_dsts write "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${TALKBOX_WRITE[@]}"
	mount_volume_args write_mounts "$container" "$TALKBOX_ROOT/defaults/write.mounts" "$(pwd)" "$HOME" "${TALKBOX_WRITE[@]}"
	port_args ports "$TALKBOX_ROOT/defaults/ports" "${TALKBOX_PORT[@]}"
	if [[ "$container" == netbox ]]; then
		deny_allow_args deny_ips allow_ips "$TALKBOX_ROOT/defaults/deny.ip" "$TALKBOX_ROOT/defaults/allow.ip" TALKBOX_DENY_IP TALKBOX_ALLOW_IP
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
		"run_${container}_recontain" "$(pwd)" "$TALKBOX_INTERACTIVE" read_mounts write_mounts write_srcs write_dsts ports deny_ips allow_ips
		;;
	rebuild)
		prepare_git_host "$(pwd)"
		"run_${container}_rebuild" "$(pwd)" "$TALKBOX_INTERACTIVE" read_mounts write_mounts write_srcs write_dsts ports deny_ips allow_ips
		;;
	rm-container)
		"run_${container}_rm_container" "$(pwd)" write_dsts
		;;
	rm-image)
		"run_${container}_rm_image" "$(pwd)"
		;;
	*)
		prepare_git_host "$(pwd)"
		"run_${container}" "$(pwd)" "$TALKBOX_COMMAND" "$TALKBOX_INTERACTIVE" read_mounts write_mounts write_srcs write_dsts ports deny_ips allow_ips
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
