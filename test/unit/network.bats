# shellcheck disable=SC2030,SC2031 # bats runs each test in a subshell; exported shim configuration is consumed only within the test that sets it
load helpers

setup() {
	ABSENT="$BATS_TEST_TMPDIR/absent.ports"
	DENY_FILE="$BATS_TEST_TMPDIR/deny.ip"
	ALLOW_FILE="$BATS_TEST_TMPDIR/allow.ip"
}

@test "port_args parses a ports file in order" {
	load_lib network.sh
	local file="$BATS_TEST_TMPDIR/ports"
	printf '8080\n9090\n' >"$file"
	local out=()
	port_args out "$file"
	[[ "${out[*]}" == '-T,8080 -T,9090' ]]
}

@test "port_args ignores blank and comment lines" {
	load_lib network.sh
	local file="$BATS_TEST_TMPDIR/ports"
	printf '# comment\n\n  # indented\n8080\n' >"$file"
	local out=()
	port_args out "$file"
	[[ "${out[*]}" == '-T,8080' ]]
}

@test "port_args strips an inline comment and keeps the port value" {
	load_lib network.sh
	local file="$BATS_TEST_TMPDIR/ports"
	printf '8080  # web server\n' >"$file"
	local out=()
	port_args out "$file"
	[[ "${out[*]}" == '-T,8080' ]]
}

@test "port_args yields no entry for a line that is only an inline comment" {
	load_lib network.sh
	local file="$BATS_TEST_TMPDIR/ports"
	printf '   # only a comment\n' >"$file"
	local out=()
	port_args out "$file"
	[[ ${#out[@]} -eq 0 ]]
}

@test "port_args yields no ports when the defaults file is absent" {
	load_lib network.sh
	local out=()
	port_args out "$ABSENT"
	[[ ${#out[@]} -eq 0 ]]
}

@test "port_args yields no ports when the defaults file is empty" {
	load_lib network.sh
	local file="$BATS_TEST_TMPDIR/ports"
	: >"$file"
	local out=()
	port_args out "$file"
	[[ ${#out[@]} -eq 0 ]]
}

@test "port_args deduplicates ports" {
	load_lib network.sh
	local file="$BATS_TEST_TMPDIR/ports"
	printf '8080\n8080\n' >"$file"
	local out=()
	port_args out "$file" 8080
	[[ "${out[*]}" == '-T,8080' ]]
}

@test "port_args unions defaults-file and CLI ports in order" {
	load_lib network.sh
	local file="$BATS_TEST_TMPDIR/ports"
	printf '8080\n' >"$file"
	local out=()
	port_args out "$file" 9090 8080
	[[ "${out[*]}" == '-T,8080 -T,9090' ]]
}

@test "deny_allow_args reads the deny file into the deny set in order" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n192.168.0.0/16\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.0.0.0/8 192.168.0.0/16' ]]
	[[ "${allow_out[*]}" == '127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "deny_allow_args unions CLI deny entries after the file entries" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_cli=(192.168.1.1)
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.0.0.0/8 192.168.1.1' ]]
}

@test "deny_allow_args accepts CLI-only deny entries when the files are absent" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	deny_cli=(10.1.1.1 2001:db8::1)
	deny_allow_args deny_out allow_out "$ABSENT" "$BATS_TEST_TMPDIR/absent.allow" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.1.1.1 2001:db8::1' ]]
}

@test "deny_allow_args ignores blank and comment lines and trims whitespace" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '# comment\n\n   \n  # indented\n  10.0.0.0/8  \n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.0.0.0/8' ]]
}

@test "deny_allow_args strips inline comments from both deny and allow file entries" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8  # Private-Use RFC 1918\n' >"$DENY_FILE"
	printf '192.168.1.1  # lab host\n' >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.0.0.0/8' ]]
	[[ "${allow_out[*]}" == '192.168.1.1 127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "deny_allow_args yields no entry for a line that is only an inline comment" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '   # only a comment\n' >"$DENY_FILE"
	printf '   # only a comment\n' >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ ${#deny_out[@]} -eq 0 ]]
	[[ "${allow_out[*]}" == '127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "deny_allow_args yields an empty deny set for absent or empty files" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	deny_allow_args deny_out allow_out "$ABSENT" "$BATS_TEST_TMPDIR/absent.allow" deny_cli allow_cli
	[[ ${#deny_out[@]} -eq 0 ]]
	[[ "${allow_out[*]}" == '127.0.0.0/8 169.254.1.1/32 ::1' ]]
	: >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ ${#deny_out[@]} -eq 0 ]]
}

@test "deny_allow_args deduplicates deny entries" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n10.0.0.0/8\n' >"$DENY_FILE"
	deny_cli=(10.0.0.0/8)
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.0.0.0/8' ]]
}

@test "deny_allow_args returns user allow entries before the always-allowed entries" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	: >"$DENY_FILE"
	printf '10.0.0.0/9\n' >"$ALLOW_FILE"
	allow_cli=(10.128.0.0/9)
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${allow_out[*]}" == '10.0.0.0/9 10.128.0.0/9 127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "deny_allow_args deduplicates allow entries including the always-allowed entries" {
	load_lib network.sh
	# shellcheck disable=SC2034 # deny_cli is passed by name to the deny_allow_args function
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	: >"$DENY_FILE"
	printf '127.0.0.0/8\n::1\n' >"$ALLOW_FILE"
	allow_cli=(::1)
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${allow_out[*]}" == '127.0.0.0/8 ::1 169.254.1.1/32' ]]
}

@test "deny_allow_args does not carve an allow entry out of an equal deny entry" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n10.1.2.3\n' >"$DENY_FILE"
	printf '10.1.2.3\n' >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.0.0.0/8 10.1.2.3' ]]
	[[ "${allow_out[*]}" == '10.1.2.3 127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "deny_allow_args keeps a broad deny CIDR whole when an allow sub-range is supplied" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n' >"$DENY_FILE"
	printf '10.0.0.0/9\n' >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.0.0.0/8' ]]
	[[ "${allow_out[*]}" == '10.0.0.0/9 127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "deny_allow_args keeps the always-allowed addresses in the deny set and the allow set" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '127.0.0.0/8\n::1\n169.254.1.1\n10.0.0.0/8\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '127.0.0.0/8 ::1 169.254.1.1 10.0.0.0/8' ]]
	[[ "${allow_out[*]}" == '127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "deny_allow_args leaves a broad IPv6 deny CIDR raw while ::1 stays in the allow set" {
	load_lib network.sh
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '::/0\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '::/0' ]]
	[[ "${allow_out[*]}" == '127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "deny_allow_args keeps a multi-entry deny set in order without carving" {
	load_lib network.sh
	# shellcheck disable=SC2034 # CLI arrays are passed by name to the deny_allow_args function
	local deny_out=() allow_out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n172.16.0.0/12\n' >"$DENY_FILE"
	printf '10.0.0.0/9\n' >"$ALLOW_FILE"
	deny_allow_args deny_out allow_out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${deny_out[*]}" == '10.0.0.0/8 172.16.0.0/12' ]]
	[[ "${allow_out[*]}" == '10.0.0.0/9 127.0.0.0/8 169.254.1.1/32 ::1' ]]
}

@test "nft_deny_ruleset emits a two-set accept-then-drop ruleset for a mixed IPv4/IPv6 deny set" {
	load_lib network.sh
	local deny=(10.0.0.0/8 192.168.1.1 2001:db8::1) allow=(127.0.0.0/8 169.254.1.1/32 ::1)
	local expected
	expected="$(
		cat <<'EOF'
add table ip talkbox_deny
add set ip talkbox_deny allowed { type ipv4_addr; flags interval; elements = { 127.0.0.0/8, 169.254.1.1/32 } }
add set ip talkbox_deny blocked { type ipv4_addr; flags interval; elements = { 10.0.0.0/8, 192.168.1.1 } }
add chain ip talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip talkbox_deny output ip daddr @allowed accept
add rule ip talkbox_deny output ip daddr @blocked drop
add table ip6 talkbox_deny
add set ip6 talkbox_deny allowed { type ipv6_addr; flags interval; elements = { ::1 } }
add set ip6 talkbox_deny blocked { type ipv6_addr; flags interval; elements = { 2001:db8::1 } }
add chain ip6 talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip6 talkbox_deny output ip6 daddr @allowed accept
add rule ip6 talkbox_deny output ip6 daddr @blocked drop
EOF
	)"
	run nft_deny_ruleset deny allow
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$expected" ]]
}

@test "nft_deny_ruleset emits only the deny set and drop rule for a deny-only family" {
	load_lib network.sh
	local deny=(10.0.0.0/8) allow=()
	local expected
	expected="$(
		cat <<'EOF'
add table ip talkbox_deny
add set ip talkbox_deny blocked { type ipv4_addr; flags interval; elements = { 10.0.0.0/8 } }
add chain ip talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip talkbox_deny output ip daddr @blocked drop
EOF
	)"
	run nft_deny_ruleset deny allow
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$expected" ]]
}

@test "nft_deny_ruleset emits only the IPv6 family for IPv6-only deny entries" {
	load_lib network.sh
	local deny=(2001:db8::1) allow=(::1)
	local expected
	expected="$(
		cat <<'EOF'
add table ip6 talkbox_deny
add set ip6 talkbox_deny allowed { type ipv6_addr; flags interval; elements = { ::1 } }
add set ip6 talkbox_deny blocked { type ipv6_addr; flags interval; elements = { 2001:db8::1 } }
add chain ip6 talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip6 talkbox_deny output ip6 daddr @allowed accept
add rule ip6 talkbox_deny output ip6 daddr @blocked drop
EOF
	)"
	run nft_deny_ruleset deny allow
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$expected" ]]
}

@test "nft_deny_ruleset emits nothing for a family present only in the allow set" {
	load_lib network.sh
	local deny=() allow=(2001:db8::1)
	run nft_deny_ruleset deny allow
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "nft_deny_ruleset emits the allow set before the deny set for a broad IPv6 deny with allows" {
	load_lib network.sh
	local deny=(::/0) allow=(::1 2001:db8::1)
	local expected
	expected="$(
		cat <<'EOF'
add table ip6 talkbox_deny
add set ip6 talkbox_deny allowed { type ipv6_addr; flags interval; elements = { ::1, 2001:db8::1 } }
add set ip6 talkbox_deny blocked { type ipv6_addr; flags interval; elements = { ::/0 } }
add chain ip6 talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip6 talkbox_deny output ip6 daddr @allowed accept
add rule ip6 talkbox_deny output ip6 daddr @blocked drop
EOF
	)"
	run nft_deny_ruleset deny allow
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$expected" ]]
}

@test "nft_deny_ruleset emits nothing for empty deny and allow sets" {
	load_lib network.sh
	local deny=() allow=()
	run nft_deny_ruleset deny allow
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "plan_nft_deny produces no invocation tokens when the deny set is empty even if the allow set is not" {
	load_lib network.sh
	local deny=() allow=(::1)
	local out=()
	plan_nft_deny out 12345 deny allow
	[[ ${#out[@]} -eq 0 ]]
}

make_podman_shim() {
	local dir="$BATS_TEST_TMPDIR/shim"
	mkdir -p "$dir"
	cat >"$dir/podman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
inspect)
	if [[ -n "${SHIM_INSPECT_RC}" && "${SHIM_INSPECT_RC}" != 0 ]]; then
		printf '%s\n' "${SHIM_INSPECT_STDERR:-podman inspect: container not found}" >&2
		exit "${SHIM_INSPECT_RC}"
	fi
	printf '%s\n' "${SHIM_PID:-4242}"
	exit 0
	;;
unshare)
	if [[ -n "${SHIM_LOG}" ]]; then
		printf 'PATH=%s\n' "$PATH" >>"${SHIM_LOG}"
	fi
	if [[ -n "${SHIM_NFT_RC}" && "${SHIM_NFT_RC}" != 0 ]]; then
		printf '%s\n' "${SHIM_NFT_STDERR:-nft: netlink error: Operation not permitted}" >&2
		exit "${SHIM_NFT_RC}"
	fi
	exit 0
	;;
esac
exit 0
EOF
	chmod +x "$dir/podman"
	printf '%s\n' "$dir"
}

path_without_sbin() {
	local -a entries=() filtered=()
	local entry out
	IFS=: read -r -a entries <<<"$PATH"
	for entry in "${entries[@]}"; do
		if [[ "$entry" != /usr/sbin && "$entry" != /sbin ]]; then
			filtered+=("$entry")
		fi
	done
	printf -v out '%s:' "${filtered[@]}"
	printf '%s\n' "${out%:}"
}

@test "install_nft_deny with an empty deny set performs no podman invocation even when the allow set is not empty" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=() allow=(127.0.0.0/8 ::1)
	local shimdir log
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -eq 0 ]]
	[[ ! -e "$log" ]]
}

@test "install_nft_deny with a non-empty deny set fails hard when podman inspect fails to return a PID" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=(10.0.0.0/8) allow=()
	local shimdir
	shimdir="$(make_podman_shim)"
	export SHIM_INSPECT_RC=1
	export SHIM_INSPECT_STDERR='Error: no container with name or ID "talkbox-proj.onbox" found'
	export PATH="$shimdir:$PATH"
	run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$output" == *'Error: no container with name or ID "talkbox-proj.onbox" found'* ]]
}

@test "install_nft_deny with a non-empty deny set fails hard when the nft pipeline exits non-zero" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=(10.0.0.0/8) allow=()
	local shimdir
	shimdir="$(make_podman_shim)"
	export SHIM_NFT_RC=1
	export SHIM_NFT_STDERR='nft: netlink error: Operation not permitted'
	export PATH="$shimdir:$PATH"
	run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$output" == *'nft: netlink error: Operation not permitted'* ]]
}

@test "install_nft_deny with a non-empty deny set applies the rules and resolves nft via the augmented sbin PATH" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=(10.0.0.0/8) allow=()
	local shimdir log first stripped
	shimdir="$(make_podman_shim)"
	log="$BATS_TEST_TMPDIR/podman.log"
	stripped="$(path_without_sbin)"
	export SHIM_LOG="$log"
	export PATH="$shimdir:$stripped"
	run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -eq 0 ]]
	[[ "$output" != *'talkbox:'* ]]
	[[ -e "$log" ]]
	IFS= read -r first <"$log"
	[[ "$first" == 'PATH=/usr/sbin:/sbin:'* ]]
}

@test "install_nft_deny with TALKBOX_STRICT_NFT=0 warns and returns 0 when podman inspect fails to return a PID" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=(10.0.0.0/8) allow=()
	local shimdir
	shimdir="$(make_podman_shim)"
	export SHIM_INSPECT_RC=1
	export TALKBOX_STRICT_NFT=0
	export PATH="$shimdir:$PATH"
	run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox: warning: cannot determine the PID of container talkbox-proj.onbox; deny/allow rules not applied'* ]]
}

@test "install_nft_deny with TALKBOX_STRICT_NFT=0 warns and returns 0 when the nft pipeline exits non-zero" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=(10.0.0.0/8) allow=()
	local shimdir
	shimdir="$(make_podman_shim)"
	export SHIM_NFT_RC=1
	export TALKBOX_STRICT_NFT=0
	export PATH="$shimdir:$PATH"
	run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox: warning: cannot apply nftables deny/allow rules in container talkbox-proj.onbox; deny list left unenforced'* ]]
}

@test "install_nft_deny in strict mode emits the exact PID-lookup failure message and returns 1" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=(10.0.0.0/8) allow=()
	local shimdir
	shimdir="$(make_podman_shim)"
	export SHIM_INSPECT_RC=1
	export SHIM_INSPECT_STDERR='Error: no container with name or ID "talkbox-proj.onbox" found'
	export PATH="$shimdir:$PATH"
	run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -eq 1 ]]
	[[ "$output" == *'talkbox: cannot determine the PID of container talkbox-proj.onbox; deny/allow rules not applied'* ]]
	[[ "$output" == *'Error: no container with name or ID "talkbox-proj.onbox" found'* ]]
}

@test "install_nft_deny in strict mode emits the exact nft-pipeline failure message and returns 1" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=(10.0.0.0/8) allow=()
	local shimdir
	shimdir="$(make_podman_shim)"
	export SHIM_NFT_RC=1
	export SHIM_NFT_STDERR='nft: netlink error: Operation not permitted'
	export PATH="$shimdir:$PATH"
	run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -eq 1 ]]
	[[ "$output" == *'talkbox: failed to apply nftables deny/allow rules in container talkbox-proj.onbox; deny list left unenforced'* ]]
	[[ "$output" == *'nft: netlink error: Operation not permitted'* ]]
}

@test "install_nft_deny with TALKBOX_STRICT_NFT=0 applies the rules and emits no warning when the nft pipeline succeeds" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the install_nft_deny function
	local deny=(10.0.0.0/8) allow=()
	local shimdir
	shimdir="$(make_podman_shim)"
	export TALKBOX_STRICT_NFT=0
	export PATH="$shimdir:$PATH"
	run install_nft_deny talkbox-proj.onbox deny allow
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}
