PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "make exposes the four test targets" {
	run make -pn
	[[ "$status" -eq 0 ]]
	[[ "$output" == *test-unit:* ]]
	[[ "$output" == *test-e2e:* ]]
	[[ "$output" == *test-canary:* ]]
	[[ "$output" == *test-timeout:* ]]
}

@test "harness writes a run record for a passing suite" {
	local dir
	dir="$(mktemp -d)"
	mkdir -p "$dir/suite"
	cat >"$dir/suite/pass.bats" <<'INNER'
@test "passing" {
	true
}
INNER
	run "$PROJECT_ROOT/test/run-suite.sh" test-smoke "$dir/suite" "$dir/record.gen.yaml"
	[[ "$status" -eq 0 ]]
	[[ -f "$dir/record.gen.yaml" ]]
	grep -q 'target: test-smoke' "$dir/record.gen.yaml"
	grep -q 'exit: 0' "$dir/record.gen.yaml"
	grep -q 'total: 1, pass: 1, fail: 0, skip: 0' "$dir/record.gen.yaml"
	rm -rf "$dir"
}

@test "harness records failing tests and exits nonzero" {
	local dir
	dir="$(mktemp -d)"
	mkdir -p "$dir/suite"
	cat >"$dir/suite/fail.bats" <<'INNER'
@test "failing" {
	false
}
INNER
	run "$PROJECT_ROOT/test/run-suite.sh" test-smoke "$dir/suite" "$dir/record.gen.yaml"
	[[ "$status" -ne 0 ]]
	[[ -f "$dir/record.gen.yaml" ]]
	grep -q 'exit: 1' "$dir/record.gen.yaml"
	grep -q 'fail: 1' "$dir/record.gen.yaml"
	grep -q "fail.bats :: failing" "$dir/record.gen.yaml"
	rm -rf "$dir"
}
