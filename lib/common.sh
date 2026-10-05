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

clean_line() {
	trim "$(strip_comment "$1")"
}

read_list_file() {
	local -n _list="$1"
	local file="$2"
	[[ -f "$file" ]] || return 0
	local line
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="$(clean_line "$line")"
		[[ -z "$line" ]] && continue
		_list+=("$line")
	done <"$file"
}

dedup_ordered() {
	local -n _out="$1"
	shift
	local -A seen=()
	local e
	_out=()
	for e in "$@"; do
		[[ -n "${seen[$e]+x}" ]] && continue
		seen[$e]=1
		_out+=("$e")
	done
}

dedup_last_ordered() {
	local -n _out="$1"
	shift
	local -a rev=() uniq=()
	local e
	for ((e = $#; e >= 1; e--)); do
		rev+=("${!e}")
	done
	dedup_ordered uniq "${rev[@]}"
	_out=()
	for ((e = ${#uniq[@]} - 1; e >= 0; e--)); do
		_out+=("${uniq[$e]}")
	done
}
