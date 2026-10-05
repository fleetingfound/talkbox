# shellcheck shell=bash
# shellcheck disable=SC2178 # out arrays are namerefs to caller-declared arrays

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"

port_args() {
	local -n _out="$1"
	local file="$2"
	shift 2
	local -a entries=() uniq=()
	read_list_file entries "$file"
	entries+=("$@")
	dedup_ordered uniq "${entries[@]}"
	_out=()
	local p
	for p in "${uniq[@]}"; do
		_out+=("-T,$p")
	done
}

deny_allow_args() {
	local -n _deny_out="$1" _allow_out="$2"
	local deny_file="$3" allow_file="$4"
	local -n _deny_cli="$5" _allow_cli="$6"
	local -a deny=() allow=()
	read_list_file deny "$deny_file"
	deny+=("${_deny_cli[@]}")
	read_list_file allow "$allow_file"
	allow+=("${_allow_cli[@]}")
	allow+=(127.0.0.0/8 169.254.1.1/32 ::1)
	dedup_ordered _deny_out "${deny[@]}"
	dedup_ordered _allow_out "${allow[@]}"
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

nft_strict() {
	[[ "${TALKBOX_STRICT_NFT:-1}" != 0 ]]
}

install_nft_deny() {
	local ctr="$1"
	local -n _deny="$2"
	if ((${#_deny[@]} == 0)); then
		return 0
	fi
	local pid
	if nft_strict; then
		pid="$(podman inspect -f '{{.State.Pid}}' "$ctr")" || {
			printf 'talkbox: cannot determine the PID of container %s; deny/allow rules not applied\n' "$ctr" >&2
			return 1
		}
	else
		pid="$(podman inspect -f '{{.State.Pid}}' "$ctr" 2>/dev/null)" || {
			printf 'talkbox: warning: cannot determine the PID of container %s; deny/allow rules not applied\n' "$ctr" >&2
			return 0
		}
	fi
	local -a cmd=()
	plan_nft_deny cmd "$pid" "$2" "$3"
	if (
		PATH="/usr/sbin:/sbin:$PATH"
		nft_deny_ruleset "$2" "$3" | "${cmd[@]}" >/dev/null
	); then
		return 0
	fi
	if nft_strict; then
		printf 'talkbox: failed to apply nftables deny/allow rules in container %s; deny list left unenforced\n' "$ctr" >&2
		return 1
	fi
	printf 'talkbox: warning: cannot apply nftables deny/allow rules in container %s; deny list left unenforced\n' "$ctr" >&2
	return 0
}
