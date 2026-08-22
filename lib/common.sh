# shellcheck shell=bash

die() {
	local message="$1" code="$2"
	printf 'talkbox: %s\n' "$message" >&2
	exit "$code"
}
