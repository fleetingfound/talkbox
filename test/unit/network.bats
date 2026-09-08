load helpers

setup() {
	ABSENT="$BATS_TEST_TMPDIR/absent.ports"
	DENY_FILE="$BATS_TEST_TMPDIR/deny.ip"
	ALLOW_FILE="$BATS_TEST_TMPDIR/allow.ip"
}

ipv4_int() {
	local o1 o2 o3 o4
	IFS=. read -r o1 o2 o3 o4 <<<"$1"
	printf '%d\n' "$(((o1 << 24) + (o2 << 16) + (o3 << 8) + o4))"
}

cidr_covers() {
	local cidr="$1" ip="$2" addr prefix net hosts ipi
	addr="${cidr%/*}"
	prefix="${cidr#*/}"
	net="$(ipv4_int "$addr")"
	hosts=$((1 << (32 - prefix)))
	ipi="$(ipv4_int "$ip")"
	[[ $ipi -ge $net && $ipi -lt $((net + hosts)) ]]
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

@test "deny_allow_args reads the deny file in order" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n192.168.0.0/16\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.0.0.0/8 192.168.0.0/16' ]]
}

@test "deny_allow_args unions CLI deny entries after the file entries" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_cli=(192.168.1.1)
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.0.0.0/8 192.168.1.1' ]]
}

@test "deny_allow_args accepts CLI-only deny entries when the files are absent" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	deny_cli=(10.1.1.1 2001:db8::1)
	deny_allow_args out "$ABSENT" "$BATS_TEST_TMPDIR/absent.allow" deny_cli allow_cli
	[[ "${out[*]}" == '10.1.1.1 2001:db8::1' ]]
}

@test "deny_allow_args ignores blank and comment lines and trims whitespace" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '# comment\n\n   \n  # indented\n  10.0.0.0/8  \n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.0.0.0/8' ]]
}

@test "deny_allow_args yields no entries for absent or empty files" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	deny_allow_args out "$ABSENT" "$BATS_TEST_TMPDIR/absent.allow" deny_cli allow_cli
	[[ ${#out[@]} -eq 0 ]]
	: >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ ${#out[@]} -eq 0 ]]
}

@test "deny_allow_args deduplicates deny entries" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n10.0.0.0/8\n' >"$DENY_FILE"
	deny_cli=(10.0.0.0/8)
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.0.0.0/8' ]]
}

@test "deny_allow_args lets an allow entry override an equal deny entry" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n10.1.2.3\n' >"$DENY_FILE"
	printf '10.1.2.3\n' >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.0.0.0/8' ]]
}

@test "deny_allow_args applies allow entries from the allow file and the CLI" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n10.1.2.3\n' >"$DENY_FILE"
	printf '# note\n\n10.1.2.3\n' >"$ALLOW_FILE"
	allow_cli=(10.0.0.0/8)
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ ${#out[@]} -eq 0 ]]
}

@test "deny_allow_args keeps the deny set when an allow entry matches nothing" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n' >"$DENY_FILE"
	printf '8.8.8.8\n' >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.0.0.0/8' ]]
}

@test "deny_allow_args always removes loopback addresses and 169.254.1.1 from the deny set" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '127.0.0.0/8\n::1\n169.254.1.1\n10.0.0.0/8\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.0.0.0/8' ]]
}

@test "deny_allow_args carves an allowed range out of a broader deny CIDR" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n' >"$DENY_FILE"
	printf '10.0.0.0/9\n' >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.128.0.0/9' ]]
}

@test "deny_allow_args carves an allowed range supplied via the CLI" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	allow_cli=(10.128.0.0/9)
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.0.0.0/9' ]]
}

@test "deny_allow_args keeps a multi-entry deny set in order while carving" {
	load_lib network.sh
	local out=() deny_cli=() allow_cli=()
	printf '10.0.0.0/8\n172.16.0.0/12\n' >"$DENY_FILE"
	printf '10.0.0.0/9\n' >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ "${out[*]}" == '10.128.0.0/9 172.16.0.0/12' ]]
}

@test "deny_allow_args carves the always-allowed DNS-forward address out of a deny CIDR that contains it" {
	load_lib network.sh
	# shellcheck disable=SC2034 # arrays are passed by name to the deny_allow_args function
	local out=() deny_cli=() allow_cli=() entry other=no
	printf '169.254.0.0/16\n' >"$DENY_FILE"
	: >"$ALLOW_FILE"
	deny_allow_args out "$DENY_FILE" "$ALLOW_FILE" deny_cli allow_cli
	[[ ${#out[@]} -gt 0 ]]
	[[ "${out[*]}" != *'169.254.0.0/16'* ]]
	for entry in "${out[@]}"; do
		if cidr_covers "$entry" 169.254.1.1; then
			return 1
		fi
		if cidr_covers "$entry" 169.254.1.2; then
			other=yes
		fi
	done
	[[ "$other" == yes ]]
}

@test "nft_deny_ruleset builds an interval-set ruleset for a mixed IPv4/IPv6 deny set" {
	load_lib network.sh
	local expected
	expected="$(
		cat <<'EOF'
add table ip talkbox_deny
add set ip talkbox_deny blocked { type ipv4_addr; flags interval; elements = { 10.0.0.0/8, 192.168.1.1 } }
add chain ip talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip talkbox_deny output ip daddr @blocked drop
add table ip6 talkbox_deny
add set ip6 talkbox_deny blocked { type ipv6_addr; flags interval; elements = { 2001:db8::1 } }
add chain ip6 talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip6 talkbox_deny output ip6 daddr @blocked drop
EOF
	)"
	run nft_deny_ruleset 10.0.0.0/8 192.168.1.1 2001:db8::1
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$expected" ]]
}

@test "nft_deny_ruleset emits only the IPv4 family for IPv4-only deny entries" {
	load_lib network.sh
	local expected
	expected="$(
		cat <<'EOF'
add table ip talkbox_deny
add set ip talkbox_deny blocked { type ipv4_addr; flags interval; elements = { 10.0.0.0/8 } }
add chain ip talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip talkbox_deny output ip daddr @blocked drop
EOF
	)"
	run nft_deny_ruleset 10.0.0.0/8
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$expected" ]]
}

@test "nft_deny_ruleset emits only the IPv6 family for IPv6-only deny entries" {
	load_lib network.sh
	local expected
	expected="$(
		cat <<'EOF'
add table ip6 talkbox_deny
add set ip6 talkbox_deny blocked { type ipv6_addr; flags interval; elements = { 2001:db8::1 } }
add chain ip6 talkbox_deny output { type filter hook output priority 0; policy accept; }
add rule ip6 talkbox_deny output ip6 daddr @blocked drop
EOF
	)"
	run nft_deny_ruleset 2001:db8::1
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$expected" ]]
}

@test "nft_deny_ruleset emits nothing for an empty deny set" {
	load_lib network.sh
	run nft_deny_ruleset
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "plan_nft_deny builds the podman unshare nsenter nft invocation tokens" {
	load_lib network.sh
	local out=()
	plan_nft_deny out 12345 10.0.0.0/8 2001:db8::1
	[[ "${out[*]}" == 'podman unshare nsenter -t 12345 -n nft -f -' ]]
}

@test "plan_nft_deny produces no invocation tokens for an empty deny set" {
	load_lib network.sh
	local out=()
	plan_nft_deny out 12345
	[[ ${#out[@]} -eq 0 ]]
}

@test "install_nft_deny with an empty deny set performs no podman invocation" {
	load_lib network.sh
	local shimdir log
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run install_nft_deny talkbox-proj.onbox
	[[ "$status" -eq 0 ]]
	[[ ! -e "$log" ]]
}

@test "install_nft_deny warns and returns success when the rules cannot be applied" {
	load_lib network.sh
	local shimdir
	shimdir="$BATS_TEST_TMPDIR/shim"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run install_nft_deny talkbox-proj.onbox 10.0.0.0/8
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox:'* ]]
}
