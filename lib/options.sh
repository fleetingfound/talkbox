#!/usr/bin/env bash

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
			printf 'talkbox: unknown option: %s\n' "$1" >&2
			return 2
			;;
		*)
			ONBOX_COMMAND="$1"
			;;
		esac
		shift
	done
}
