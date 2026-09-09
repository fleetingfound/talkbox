# shellcheck shell=bash

die() {
	local message="$1" code="$2"
	printf 'talkbox: %s\n' "$message" >&2
	exit "$code"
}

strip_comment() {
	local s="$1"
	printf '%s' "${s%%#*}"
}

trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}
