# shellcheck shell=bash
# shellcheck disable=SC2178 # out arrays are namerefs to caller-declared arrays

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

ipv4_int() {
	local o1 o2 o3 o4
	IFS=. read -r o1 o2 o3 o4 <<<"$1"
	printf '%d\n' "$(((o1 << 24) + (o2 << 16) + (o3 << 8) + o4))"
}

ipv4_str() {
	local n="$1"
	printf '%d.%d.%d.%d\n' "$((n >> 24 & 255))" "$((n >> 16 & 255))" "$((n >> 8 & 255))" "$((n & 255))"
}

ipv4_prefix() {
	local size="$1" p=32
	while ((size > 1)); do
		((size >>= 1))
		((p--))
	done
	printf '%d\n' "$p"
}

ipv4_range() {
	local entry="$1" addr prefix start
	addr="${entry%/*}"
	if [[ "$entry" == */* ]]; then
		prefix="${entry#*/}"
	else
		prefix=32
	fi
	start="$(ipv4_int "$addr")"
	printf '%d %d\n' "$start" "$((start + (1 << (32 - prefix)) - 1))"
}

range_cidrs() {
	local -n _out="$1"
	local start="$2" end="$3" size next
	local s="$start"
	while ((s <= end)); do
		size=1
		while true; do
			next=$((size << 1))
			((next <= 1 << 31)) || break
			((s & (next - 1))) && break
			((s + next - 1 > end)) && break
			size=$next
		done
		_out+=("$(ipv4_str "$s")/$(ipv4_prefix "$size")")
		s=$((s + size))
	done
}

deny_allow_subtract() {
	local -n _out="$1"
	local deny="$2"
	shift 2
	local -a allow=("$@")
	local a
	if [[ "$deny" == *:* ]]; then
		for a in "${allow[@]}"; do
			[[ "$a" == *:* ]] || continue
			if [[ "$a" == "$deny" || "${a%/*}" == "$deny" || ("$a" != */* && "$deny" == "$a/128") ]]; then
				return 0
			fi
		done
		_out+=("$deny")
		return 0
	fi
	local ds de
	read -r ds de <<<"$(ipv4_range "$deny")"
	local -a iv=("$ds" "$de")
	for a in "${allow[@]}"; do
		[[ "$a" == *:* ]] && continue
		if [[ "$a" != */* ]]; then
			[[ "$a" == "$deny" ]] && return 0
			continue
		fi
		local as ae
		read -r as ae <<<"$(ipv4_range "$a")"
		local -a nv=()
		local i l r
		for ((i = 0; i < ${#iv[@]}; i += 2)); do
			l="${iv[$i]}"
			r="${iv[$((i + 1))]}"
			if ((as <= l && ae >= r)); then
				continue
			fi
			if ((ae < l || as > r)); then
				nv+=("$l" "$r")
				continue
			fi
			if ((l <= as - 1)); then
				nv+=("$l" "$((as - 1))")
			fi
			if ((ae + 1 <= r)); then
				nv+=("$((ae + 1))" "$r")
			fi
		done
		iv=("${nv[@]}")
		if ((${#iv[@]} == 0)); then
			return 0
		fi
	done
	if [[ "$deny" != */* ]]; then
		_out+=("$deny")
		return 0
	fi
	local -a cidrs=()
	local i
	for ((i = 0; i < ${#iv[@]}; i += 2)); do
		range_cidrs cidrs "${iv[$i]}" "${iv[$((i + 1))]}"
	done
	_out+=("${cidrs[@]}")
}

deny_allow_args() {
	local -n _out="$1" _deny_cli="$4" _allow_cli="$5"
	local deny_file="$2" allow_file="$3"
	local -a deny=() allow=()
	local line
	if [[ -f "$deny_file" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			line="$(trim "$line")"
			[[ -z "$line" || "$line" == '#'* ]] && continue
			deny+=("$line")
		done <"$deny_file"
	fi
	deny+=("${_deny_cli[@]}")
	if [[ -f "$allow_file" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			line="$(trim "$line")"
			[[ -z "$line" || "$line" == '#'* ]] && continue
			allow+=("$line")
		done <"$allow_file"
	fi
	allow+=("${_allow_cli[@]}")
	allow+=(127.0.0.0/8 169.254.1.1/32 ::1)
	local -A seen=()
	local -a dd=()
	for line in "${deny[@]}"; do
		if [[ -z "${seen[$line]+x}" ]]; then
			seen[$line]=1
			dd+=("$line")
		fi
	done
	_out=()
	local d
	for d in "${dd[@]}"; do
		deny_allow_subtract "${!_out}" "$d" "${allow[@]}"
	done
}

nft_deny_family_ruleset() {
	local family="$1" type="$2" daddr="$3"
	shift 3
	if (($# == 0)); then
		return
	fi
	printf 'add table %s talkbox_deny\n' "$family"
	printf 'add set %s talkbox_deny blocked { type %s; flags interval; elements = { ' "$family" "$type"
	local i sep=''
	for ((i = 1; i <= $#; i++)); do
		printf '%s%s' "$sep" "${!i}"
		sep=', '
	done
	printf ' } }\n'
	printf 'add chain %s talkbox_deny output { type filter hook output priority 0; policy accept; }\n' "$family"
	printf 'add rule %s talkbox_deny output %s daddr @blocked drop\n' "$family" "$daddr"
}

nft_deny_ruleset() {
	local -a v4=() v6=() entry
	for entry in "$@"; do
		if [[ "$entry" == *:* ]]; then
			v6+=("$entry")
		else
			v4+=("$entry")
		fi
	done
	nft_deny_family_ruleset ip ipv4_addr ip "${v4[@]}"
	nft_deny_family_ruleset ip6 ipv6_addr ip6 "${v6[@]}"
}

plan_nft_deny() {
	local -n _out="$1"
	local pid="$2"
	shift 2
	if (($# > 0)); then
		_out+=("podman" "unshare" "nsenter" "-t" "$pid" "-n" "nft" "-f" "-")
	fi
}

install_nft_deny() {
	local ctr="$1"
	shift
	if (($# == 0)); then
		return 0
	fi
	local pid
	pid="$(podman inspect -f '{{.State.Pid}}' "$ctr" 2>/dev/null)" || {
		printf 'talkbox: warning: cannot determine the PID of container %s; deny/allow rules not applied\n' "$ctr" >&2
		return 0
	}
	local -a cmd=()
	plan_nft_deny cmd "$pid" "$@"
	if ! nft_deny_ruleset "$@" | "${cmd[@]}" >/dev/null 2>&1; then
		printf 'talkbox: warning: cannot apply nftables deny/allow rules in container %s; deny list left unenforced\n' "$ctr" >&2
	fi
	return 0
}
