# shellcheck shell=bash

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"
source "$TALKBOX_ROOT/lib/naming.sh"

mount_spec() {
	local -n _src="$1" _dst="$2"
	local spec="$3" s d
	if [[ "$spec" == *:* ]]; then
		s="${spec%%:*}"
		d="${spec#*:}"
	else
		s="$spec"
		d=""
	fi
	_src="$(trim "$s")"
	_dst="$(trim "$d")"
}

expand_mount() {
	local mode="$1" s="$2" d="$3" project="$4" home="$5"
	local -n _src="$6" _dst="$7"
	s="${s//\$HOME/$home}"
	if [[ "$s" == '~'* ]]; then
		s="$home${s#\~}"
	fi
	if [[ -z "$d" ]]; then
		d="/host/$mode/$(basename "$s")"
	fi
	d="${d//\$PROJECT//working/$(project_base "$project")}"
	d="${d//\$HOME/$home}"
	if [[ "$d" == '~'* ]]; then
		d="$home${d#\~}"
	fi
	_src="$s"
	_dst="$d"
}

dest_depth() {
	local d="$1" slashes
	d="${d#/}"
	[[ -z "$d" ]] && {
		printf '0\n'
		return
	}
	slashes="${d//[^\/]/}"
	printf '%d\n' "$((${#slashes} + 1))"
}

mount_args() {
	local -n _out="$1"
	local mode="$2" file="$3" project="$4" home="$5"
	shift 5
	local -a cli_specs=("$@")
	local -a srcs=() dsts=()
	local line src dst
	if [[ -f "$file" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			line="$(trim "$line")"
			[[ -z "$line" || "$line" == '#'* ]] && continue
			mount_spec src dst "$line"
			expand_mount "$mode" "$src" "$dst" "$project" "$home" src dst
			srcs+=("$src")
			dsts+=("$dst")
		done <"$file"
	fi
	local spec
	for spec in "${cli_specs[@]}"; do
		spec="$(trim "$spec")"
		[[ -z "$spec" || "$spec" == '#'* ]] && continue
		mount_spec src dst "$spec"
		expand_mount "$mode" "$src" "$dst" "$project" "$home" src dst
		srcs+=("$src")
		dsts+=("$dst")
	done
	local -A seen=()
	local -a usrcs=() udsts=() depthlines=() idx=()
	local i j
	for ((i = ${#srcs[@]} - 1; i >= 0; i--)); do
		if [[ -z "${seen[${dsts[$i]}]+x}" ]]; then
			seen["${dsts[$i]}"]=1
			usrcs=("${srcs[$i]}" "${usrcs[@]}")
			udsts=("${dsts[$i]}" "${udsts[@]}")
		fi
	done
	for ((j = 0; j < ${#udsts[@]}; j++)); do
		depthlines+=("$(dest_depth "${udsts[$j]}") $j")
	done
	if ((${#depthlines[@]} > 0)); then
		mapfile -t idx < <(printf '%s\n' "${depthlines[@]}" | sort -n -s -k1,1 | cut -d' ' -f2)
	fi
	local ro=""
	[[ "$mode" == read ]] && ro=":ro"
	_out=()
	for j in "${idx[@]}"; do
		_out+=("-v" "${usrcs[$j]}:${udsts[$j]}$ro")
	done
}
