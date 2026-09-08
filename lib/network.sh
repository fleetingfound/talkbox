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

deny_allow_args() {
	local -n _deny_out="$1" _allow_out="$2"
	local deny_file="$3" allow_file="$4"
	local -n _deny_cli="$5" _allow_cli="$6"
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
	local e
	_deny_out=()
	for e in "${deny[@]}"; do
		if [[ -z "${seen[$e]+x}" ]]; then
			seen[$e]=1
			_deny_out+=("$e")
		fi
	done
	seen=()
	_allow_out=()
	for e in "${allow[@]}"; do
		if [[ -z "${seen[$e]+x}" ]]; then
			seen[$e]=1
			_allow_out+=("$e")
		fi
	done
}

nft_interval_set() {
	local family="$1" type="$2" name="$3"
	shift 3
	printf 'add set %s talkbox_deny %s { type %s; flags interval; elements = { ' "$family" "$name" "$type"
	local i sep=''
	for ((i = 1; i <= $#; i++)); do
		printf '%s%s' "$sep" "${!i}"
		sep=', '
	done
	printf ' } }\n'
}

nft_deny_family_ruleset() {
	local family="$1" type="$2" daddr="$3"
	local -n _deny="$4" _allow="$5"
	if ((${#_deny[@]} == 0)); then
		return 0
	fi
	printf 'add table %s talkbox_deny\n' "$family"
	if ((${#_allow[@]} > 0)); then
		nft_interval_set "$family" "$type" allowed "${_allow[@]}"
	fi
	nft_interval_set "$family" "$type" blocked "${_deny[@]}"
	printf 'add chain %s talkbox_deny output { type filter hook output priority 0; policy accept; }\n' "$family"
	if ((${#_allow[@]} > 0)); then
		printf 'add rule %s talkbox_deny output %s daddr @allowed accept\n' "$family" "$daddr"
	fi
	printf 'add rule %s talkbox_deny output %s daddr @blocked drop\n' "$family" "$daddr"
}

nft_deny_ruleset() {
	local -n _deny="$1" _allow="$2"
	local -a deny4=() allow4=() deny6=() allow6=() entry
	for entry in "${_deny[@]}"; do
		if [[ "$entry" == *:* ]]; then
			deny6+=("$entry")
		else
			deny4+=("$entry")
		fi
	done
	for entry in "${_allow[@]}"; do
		if [[ "$entry" == *:* ]]; then
			allow6+=("$entry")
		else
			allow4+=("$entry")
		fi
	done
	nft_deny_family_ruleset ip ipv4_addr ip deny4 allow4
	nft_deny_family_ruleset ip6 ipv6_addr ip6 deny6 allow6
}

plan_nft_deny() {
	local -n _out="$1"
	local pid="$2"
	local -n _deny="$3"
	if ((${#_deny[@]} > 0)); then
		_out+=("podman" "unshare" "nsenter" "-t" "$pid" "-n" "nft" "-f" "-")
	fi
}

install_nft_deny() {
	local ctr="$1"
	local -n _deny="$2"
	if ((${#_deny[@]} == 0)); then
		return 0
	fi
	local pid
	pid="$(podman inspect -f '{{.State.Pid}}' "$ctr" 2>/dev/null)" || {
		printf 'talkbox: warning: cannot determine the PID of container %s; deny/allow rules not applied\n' "$ctr" >&2
		return 0
	}
	local -a cmd=()
	plan_nft_deny cmd "$pid" "$2" "$3"
	if ! nft_deny_ruleset "$2" "$3" | "${cmd[@]}" >/dev/null 2>&1; then
		printf 'talkbox: warning: cannot apply nftables deny/allow rules in container %s; deny list left unenforced\n' "$ctr" >&2
	fi
	return 0
}
