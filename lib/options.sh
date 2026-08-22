# shellcheck shell=bash

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"

# shellcheck disable=SC2034
parse_onbox_options() {
	ONBOX_COMMAND=""
	ONBOX_INTERACTIVE="yes"
	ONBOX_VERB=""
	ONBOX_READ=()
	ONBOX_WRITE=()
	ONBOX_PORT=()
	ONBOX_FRESH="no"
	ONBOX_INHERIT=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-c | --command) ;;
		--interactive)
			ONBOX_INTERACTIVE="yes"
			;;
		--noninteractive)
			ONBOX_INTERACTIVE="no"
			;;
		--read)
			shift
			ONBOX_READ+=("$1")
			;;
		--write)
			shift
			ONBOX_WRITE+=("$1")
			;;
		--port)
			shift
			ONBOX_PORT+=("$1")
			;;
		--fresh)
			ONBOX_FRESH="yes"
			;;
		--inherit)
			shift
			ONBOX_INHERIT="$1"
			;;
		--recontain)
			ONBOX_VERB="recontain"
			;;
		--rebuild)
			ONBOX_VERB="rebuild"
			;;
		--rm-container)
			ONBOX_VERB="rm-container"
			;;
		--rm-image)
			ONBOX_VERB="rm-image"
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
