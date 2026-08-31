# shellcheck shell=bash

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"

# shellcheck disable=SC2034
parse_talkbox_options() {
	TALKBOX_COMMAND=""
	TALKBOX_INTERACTIVE="yes"
	TALKBOX_VERB=""
	TALKBOX_ALL="no"
	TALKBOX_BRANCH=""
	TALKBOX_READ=()
	TALKBOX_WRITE=()
	TALKBOX_PORT=()
	TALKBOX_FRESH="no"
	TALKBOX_INHERIT=""
	local after_command=no
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-c | --command)
			after_command=yes
			;;
		--interactive)
			TALKBOX_INTERACTIVE="yes"
			;;
		--noninteractive)
			TALKBOX_INTERACTIVE="no"
			;;
		--read)
			shift
			TALKBOX_READ+=("$1")
			;;
		--write)
			shift
			TALKBOX_WRITE+=("$1")
			;;
		--port)
			shift
			TALKBOX_PORT+=("$1")
			;;
		--fresh)
			TALKBOX_FRESH="yes"
			;;
		--inherit)
			shift
			TALKBOX_INHERIT="$1"
			;;
		--all)
			TALKBOX_ALL="yes"
			;;
		fetch | merge | sync)
			if [[ "$after_command" == yes ]]; then
				TALKBOX_COMMAND="$1"
			else
				TALKBOX_VERB="$1"
			fi
			;;
		--recontain)
			TALKBOX_VERB="recontain"
			;;
		--rebuild)
			TALKBOX_VERB="rebuild"
			;;
		--rm-container)
			TALKBOX_VERB="rm-container"
			;;
		--rm-image)
			TALKBOX_VERB="rm-image"
			;;
		-*)
			die "unknown option: $1" 2
			;;
		*)
			if [[ "$after_command" == yes ]]; then
				TALKBOX_COMMAND="$1"
			elif [[ "$TALKBOX_VERB" == merge || "$TALKBOX_VERB" == sync ]]; then
				TALKBOX_BRANCH="$1"
			else
				TALKBOX_COMMAND="$1"
			fi
			;;
		esac
		shift
	done
}
