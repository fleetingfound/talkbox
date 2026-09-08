load helpers

setup() {
	ABSENT="$BATS_TEST_TMPDIR/absent.ports"
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
