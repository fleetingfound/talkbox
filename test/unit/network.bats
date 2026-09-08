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
