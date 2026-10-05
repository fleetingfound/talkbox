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

mount_entries() {
	local -n _esrcs="$1" _edsts="$2"
	local mode="$3" file="$4" project="$5" home="$6"
	shift 6
	local -a cli_specs=("$@")
	local -a lines=() lsrcs=() ldsts=()
	read_list_file lines "$file"
	local line src dst spec
	for line in "${lines[@]}"; do
		mount_spec src dst "$line"
		expand_mount "$mode" "$src" "$dst" "$project" "$home" src dst
		lsrcs+=("$src")
		ldsts+=("$dst")
	done
	for spec in "${cli_specs[@]}"; do
		spec="$(clean_line "$spec")"
		[[ -z "$spec" ]] && continue
		mount_spec src dst "$spec"
		expand_mount "$mode" "$src" "$dst" "$project" "$home" src dst
		lsrcs+=("$src")
		ldsts+=("$dst")
	done
	local -A src_of=()
	local i
	for ((i = 0; i < ${#ldsts[@]}; i++)); do
		src_of["${ldsts[$i]}"]="${lsrcs[$i]}"
	done
	local -a udsts=() depthlines=() idx=()
	dedup_last_ordered udsts "${ldsts[@]}"
	for ((i = 0; i < ${#udsts[@]}; i++)); do
		depthlines+=("$(dest_depth "${udsts[$i]}") $i")
	done
	if ((${#depthlines[@]} > 0)); then
		mapfile -t idx < <(printf '%s\n' "${depthlines[@]}" | sort -n -s -k1,1 | cut -d' ' -f2)
	fi
	_esrcs=()
	_edsts=()
	for i in "${idx[@]}"; do
		_esrcs+=("${src_of[${udsts[$i]}]}")
		_edsts+=("${udsts[$i]}")
	done
}

mount_args() {
	local -n _out="$1"
	local mode="$2" file="$3" project="$4" home="$5"
	shift 5
	local -a srcs=() dsts=()
	mount_entries srcs dsts "$mode" "$file" "$project" "$home" "$@"
	local ro=""
	[[ "$mode" == read ]] && ro=":ro"
	local i
	_out=()
	for ((i = 0; i < ${#srcs[@]}; i++)); do
		_out+=("-v" "${srcs[$i]}:${dsts[$i]}$ro")
	done
}

mount_volume_args() {
	local -n _out="$1"
	local container="$2" project="$3"
	local -n _srcs="$4" _dsts="$5"
	local i vol
	_out=()
	for ((i = 0; i < ${#_srcs[@]}; i++)); do
		if [[ "$container" == offbox ]]; then
			vol="$(offbox_write_volume "$project" "$(dest_slug "${_dsts[$i]}")")"
		else
			vol="$(netbox_write_volume "$project" "$(dest_slug "${_dsts[$i]}")")"
		fi
		_out+=("-v" "$vol:${_dsts[$i]}")
	done
}
