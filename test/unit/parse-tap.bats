load helpers

setup() {
	source "$PROJECT_ROOT/test/lib.bash"
}

feed_tap() {
	local tap_file="$BATS_TEST_TMPDIR/tap.log"
	cat >"$tap_file"
	parse_tap "$tap_file"
}

@test "failing test with a diagnostic is recorded as src :: name" {
	feed_tap <<'EOF'
1..1
not ok 1 a failing named test
# (in test file named.bats, line 1)
#   `@test "a failing named test" { false; }' failed
EOF
	[[ "$FAIL" -eq 1 ]]
	[[ "${#FAIL_NAMES[@]}" -eq 1 ]]
	[[ "${FAIL_NAMES[0]}" == "named.bats :: a failing named test" ]]
}

@test "failing test with an empty description and a diagnostic is recorded" {
	feed_tap <<'EOF'
1..1
not ok 1 
# (in test file empty.bats, line 1)
#   `@test "" { false; }' failed
EOF
	[[ "$FAIL" -eq 1 ]]
	[[ "${#FAIL_NAMES[@]}" -eq "$FAIL" ]]
	[[ "${FAIL_NAMES[0]}" == "empty.bats :: (unnamed)" ]]
}

@test "failing test with an empty description and a directive is recorded" {
	feed_tap <<'EOF'
1..1
not ok 1  # timeout after 1s
# (in test file empty_timeout.bats, line 1)
#   `@test "" { sleep 30; }' failed
EOF
	[[ "$FAIL" -eq 1 ]]
	[[ "${#FAIL_NAMES[@]}" -eq "$FAIL" ]]
	[[ "${FAIL_NAMES[0]}" == "empty_timeout.bats :: (unnamed)" ]]
}

@test "failing test without a diagnostic falls back to (unknown) :: pending" {
	feed_tap <<'EOF'
1..1
not ok 1 a failing named test
EOF
	[[ "$FAIL" -eq 1 ]]
	[[ "${#FAIL_NAMES[@]}" -eq "$FAIL" ]]
	[[ "${FAIL_NAMES[0]}" == "(unknown) :: a failing named test" ]]
}

@test "failing test with an empty description and no diagnostic falls back to (unknown) :: (unnamed)" {
	feed_tap <<'EOF'
1..1
not ok 1 
EOF
	[[ "$FAIL" -eq 1 ]]
	[[ "${#FAIL_NAMES[@]}" -eq "$FAIL" ]]
	[[ "${FAIL_NAMES[0]}" == "(unknown) :: (unnamed)" ]]
}

@test "passing and skipped lines leave FAIL and FAIL_NAMES untouched" {
	feed_tap <<'EOF'
1..2
ok 1 a passing test
ok 2 a skipped test # skip
EOF
	[[ "$TOTAL" -eq 2 ]]
	[[ "$PASS" -eq 1 ]]
	[[ "$SKIP" -eq 1 ]]
	[[ "$FAIL" -eq 0 ]]
	[[ "${#FAIL_NAMES[@]}" -eq 0 ]]
}
