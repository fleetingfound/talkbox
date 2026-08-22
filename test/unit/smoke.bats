PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "harness exposes a positive global test timeout" {
	[[ "$GLOBAL_TEST_TIMEOUT" =~ ^[0-9]+$ && "$GLOBAL_TEST_TIMEOUT" -gt 0 ]]
}

@test "harness exposes a positive individual test timeout" {
	[[ "$INDIVIDUAL_TEST_TIMEOUT" =~ ^[0-9]+$ && "$INDIVIDUAL_TEST_TIMEOUT" -gt 0 ]]
}

@test "harness provides an isolated temporary directory per test" {
	[[ -d "$BATS_TEST_TMPDIR" && -w "$BATS_TEST_TMPDIR" ]]
}

@test "harness can locate the bats executable" {
	command -v bats >/dev/null
}

@test "harness runner is a bash script with valid syntax" {
	run bash -n "$PROJECT_ROOT/test/run-suite.sh"
	[[ "$status" -eq 0 ]]
}

@test "dispatcher rejects an unknown container name with exit code 2" {
	run "$PROJECT_ROOT/talkbox.sh" bogus
	[[ "$status" -eq 2 ]]
	[[ "$output" == *"talkbox: unknown container: bogus"* ]]
}
