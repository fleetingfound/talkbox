#!/usr/bin/env bash
set -euo pipefail

TALKBOX_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export TALKBOX_ROOT

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
		printf 'usage: talkbox.sh <onbox|netbox|offbox> ...\n' >&2
		exit 2
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
	printf 'talkbox: %s is not implemented yet\n' "$container" >&2
	exit 1
	;;
*)
	printf 'talkbox: unknown container: %s\n' "$container" >&2
	exit 2
	;;
esac
