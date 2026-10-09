load helpers

SUITE_PID=''
SUITE_UNIT=''
NESTED_UNIT=''

teardown() {
	if [[ -n "$NESTED_UNIT" ]]; then
		systemctl --user stop "$NESTED_UNIT" 2>/dev/null || true
		NESTED_UNIT=''
	fi
	if [[ -n "$SUITE_UNIT" ]]; then
		systemctl --user stop "$SUITE_UNIT" 2>/dev/null || true
		SUITE_UNIT=''
	fi
	if [[ -n "$SUITE_PID" ]]; then
		kill "$SUITE_PID" 2>/dev/null || true
		SUITE_PID=''
	fi
}

unit_property() {
	systemctl --user show -p "$2" --value "$1" 2>/dev/null || true
}

# shellcheck disable=SC2016 # the script text is expanded inside the nested unit
own_nested_unit_cmd='u="$(basename "$(sed -n "s/^0:://p" /proc/self/cgroup)")"; systemctl --user show -p StopPropagatedFrom --value "$u"'

@test "sdrun declares StopPropagatedFrom on the exported suite unit" {
	local wrapper out
	wrapper="talkbox-test-sdrun-prop-$$-$(date +%s).service"
	# shellcheck disable=SC2034,SC2030 # read by sdrun when it builds the systemd-run invocation
	TALKBOX_SUITE_UNIT="$wrapper"
	out="$(sdrun bash -c "$own_nested_unit_cmd" 2>/dev/null)"
	unset TALKBOX_SUITE_UNIT
	[[ "$out" == *"$wrapper"* ]]
}

@test "sdrun omits StopPropagatedFrom without an exported suite unit" {
	local out
	unset TALKBOX_SUITE_UNIT
	out="$(sdrun bash -c "$own_nested_unit_cmd" 2>/dev/null)"
	[[ -z "$out" ]]
}

@test "a nested sdrun unit is stopped when the suite wrapper unit is stopped" {
	# shellcheck disable=SC2031 # unset or set per test inside this test's subshell
	if [[ -z "${TALKBOX_SUITE_UNIT:-}" ]]; then
		skip 'no suite wrapper unit exported; run the suite via make'
	fi
	local dir info unit_file wrapper n
	dir="$BATS_TEST_TMPDIR"
	info="$dir/suite-unit.info"
	unit_file="$dir/nested-unit.info"
	mkdir -p "$dir/suite"
	# shellcheck disable=SC2016 # $-expansions are evaluated inside the generated suite
	cat >"$dir/suite/prop.bats" <<INNER
source '$PROJECT_ROOT/test/e2e/helpers.bash'

@test "records the suite unit and starts a nested sleeper" {
	printf '%s\n' "\${TALKBOX_SUITE_UNIT:-}" >"$info"
	sdrun bash -c 'basename "\$(sed -n "s/^0:://p" /proc/self/cgroup)" >\$1; sleep 20' _ '$unit_file' &
	wait "\$!" || true
}
INNER
	GLOBAL_TEST_TIMEOUT=120 INDIVIDUAL_TEST_TIMEOUT=45 \
		"$PROJECT_ROOT/test/run-suite.sh" test-sdrun-prop "$dir/suite" "$dir/record.gen.yaml" \
		>"$dir/suite.log" 2>&1 &
	SUITE_PID=$!
	for ((n = 0; n < 100; n++)); do
		if [[ -s "$unit_file" ]] || ! kill -0 "$SUITE_PID" 2>/dev/null; then
			break
		fi
		sleep 0.2
	done
	[[ -s "$unit_file" ]]
	NESTED_UNIT="$(<"$unit_file")"
	wrapper="$(<"$info")"
	SUITE_UNIT="$wrapper"
	[[ "$wrapper" == talkbox-*.service ]]
	[[ "$(unit_property "$NESTED_UNIT" StopPropagatedFrom)" == "$wrapper" ]]
	[[ "$(unit_property "$NESTED_UNIT" ActiveState)" == active ]]
	systemctl --user stop "$wrapper"
	for ((n = 0; n < 100; n++)); do
		[[ "$(unit_property "$NESTED_UNIT" ActiveState)" != active ]] && break
		sleep 0.2
	done
	[[ "$(unit_property "$NESTED_UNIT" ActiveState)" != active ]]
	for ((n = 0; n < 100; n++)); do
		if ! kill -0 "$SUITE_PID" 2>/dev/null; then
			break
		fi
		sleep 0.2
	done
	wait "$SUITE_PID" 2>/dev/null || true
	[[ -s "$dir/record.gen.yaml" ]]
	SUITE_PID=''
	SUITE_UNIT=''
	NESTED_UNIT=''
}
