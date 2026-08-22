# shellcheck shell=bash

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"

# shellcheck disable=SC2034
parse_onbox_options() {
	ONBOX_COMMAND=""
	ONBOX_INTERACTIVE="yes"
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-c | --command) ;;
		--interactive)
			ONBOX_INTERACTIVE="yes"
			;;
		--noninteractive)
			ONBOX_INTERACTIVE="no"
			;;
		-*)
			die "unknown option: $1" 2
			;;
		*)
			ONBOX_COMMAND="$1"
			;;
		esac
		shift
	done
}
