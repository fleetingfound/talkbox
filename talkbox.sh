#!/usr/bin/env bash
set -euo pipefail

TALKBOX_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export TALKBOX_ROOT

source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"
source "$TALKBOX_ROOT/lib/options.sh"
source "$TALKBOX_ROOT/lib/containers.sh"

onbox_action() {
	parse_onbox_options "$@"
	ensure_base_image
	run_onbox "$(pwd)" "$ONBOX_COMMAND" "$ONBOX_INTERACTIVE"
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
