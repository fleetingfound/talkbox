# shellcheck shell=bash

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"

port_args() {
	local -n _out="$1"
	local file="$2"
	shift 2
	local -a cli_ports=("$@")
	local -a list=()
	local line
	if [[ -f "$file" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			line="$(trim "$line")"
			[[ -z "$line" || "$line" == '#'* ]] && continue
			list+=("$line")
		done <"$file"
	fi
	list+=("${cli_ports[@]}")
	local -A seen=()
	local p
	_out=()
	for p in "${list[@]}"; do
		if [[ -z "${seen[$p]+x}" ]]; then
			seen[$p]=1
			_out+=("-T,$p")
		fi
	done
}
