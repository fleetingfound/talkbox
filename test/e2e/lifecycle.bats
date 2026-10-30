load helpers

setup() {
	e2e_setup
	CTR="$ONBOX_CTR"
}

teardown() {
	e2e_teardown
}

@test "onbox creates a persistent container that survives after the shell exits" {
	local exp
	exp="$(mktemp --suffix=.exp)"
	cat >"$exp" <<'EXPECT'
set timeout 30
cd [lindex $argv 0]
spawn "[lindex $argv 1]/talkbox.sh" onbox
send "exit\r"
expect eof
EXPECT
	run sdrun expect "$exp" "$PROJECT" "$TALKBOX"
	[[ "$status" -eq 0 ]]
	run sdrun podman container exists "$CTR"
	[[ "$status" -eq 0 ]]
	rm -f "$exp"
}

@test "onbox -c <command> runs within the same persistent container" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo probe > /tmp/talkbox-persist-probe'
	[[ "$status" -eq 0 ]]
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'cat /tmp/talkbox-persist-probe'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'probe'* ]]
}

@test "onbox --read exposes a read-only mount inside the container" {
	local src
	src="$(mktemp)"
	printf 'mountable-config\n' >"$src"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --read "$src" -c --noninteractive "cat /host/read/$(basename "$src")"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'mountable-config'* ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --read "$src" -c --noninteractive "touch /host/read/$(basename "$src")"
	[[ "$status" -ne 0 ]]
	rm -f "$src"
}

@test "onbox --write exposes a writable mount inside the container" {
	local data
	data="$(mktemp -d)"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --write "$data" -c --noninteractive "echo written > /host/write/$(basename "$data")/out.txt"
	[[ "$status" -eq 0 ]]
	[[ -f "$data/out.txt" ]]
	[[ "$(cat "$data/out.txt")" == 'written' ]]
	rm -rf "$data"
}

@test "onbox --port makes a host port reachable inside the container" {
	command -v python3 >/dev/null 2>&1 || skip "python3 is required for the port e2e test"
	local www port srv
	www="$(mktemp -d)"
	printf 'port-marker\n' >"$www/marker"
	start_host_http_server "$www" srv port
	e2e_register_pid "$srv"
	wait_for_http "http://127.0.0.1:$port/marker"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --port "$port" -c --noninteractive "curl -fsS --max-time 10 http://127.0.0.1:$port/marker"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'port-marker'* ]]
	kill "$srv" 2>/dev/null || true
	e2e_clear_pids
	rm -rf "$www"
}

@test "onbox --rm-container removes the persistent container and its gitdir named volume" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'true'
	[[ "$status" -eq 0 ]]
	run sdrun podman container exists "$CTR"
	[[ "$status" -eq 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.onbox.gitdir"
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --rm-container
	[[ "$status" -eq 0 ]]
	run sdrun podman container exists "$CTR"
	[[ "$status" -ne 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.onbox.gitdir"
	[[ "$status" -ne 0 ]]
}

@test "onbox --recontain recreates the container and starts it" {
	git -C "$PROJECT" commit -q --allow-empty -m host-initial
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo stale > /tmp/talkbox-recontain-probe && git config user.email c@example.com && git config user.name container && git commit --allow-empty -m container-commit && git log --oneline | grep -q container-commit && echo PRESENT'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'PRESENT'* ]]
	local log shimdir
	log="$BATS_TEST_TMPDIR/podman-recontain.log"
	shimdir="$(mk_podman_logging_shim "$log")"
	e2e_register_dir "$shimdir"
	e2e_use_podman_shim "$shimdir"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --recontain
	[[ "$status" -eq 0 ]]
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'test ! -e /tmp/talkbox-recontain-probe && (git log --oneline | grep -q container-commit && echo STALE || echo FRESH)'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'FRESH'* ]]
	local start_line setup_line stop_line
	start_line="$(log_line_no "^start $CTR$" "$log")"
	setup_line="$(log_line_no "exec $CTR setup.sh$" "$log")"
	stop_line="$(log_line_no "^stop -t 5 $CTR$" "$log")"
	[[ -n "$start_line" && -n "$setup_line" && -n "$stop_line" ]]
	[[ "$start_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$stop_line" ]]
}

@test "onbox --rebuild rebuilds the base image and starts the container" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --rebuild
	[[ "$status" -eq 0 ]]
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'pwd'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"/working/$PROJECT_BASE"* ]]
}

wait_for_session_marker() {
	local marker="$1" n
	for ((n = 0; n < 80; n++)); do
		[[ -f "$marker" ]] && return 0
		sleep 0.5
	done
	return 1
}

wait_for_container_e2e() {
	local ctr="$1" n
	for ((n = 0; n < 60; n++)); do
		sdrun podman container exists "$ctr" >/dev/null 2>&1 && return 0
		sleep 0.5
	done
	return 1
}

wait_until_stopped() {
	local ctr="$1" n
	for ((n = 0; n < 60; n++)); do
		container_stopped "$ctr" && return 0
		sleep 0.5
	done
	return 1
}

container_exec_sessions() {
	sdrun podman inspect -f '{{json .ExecIDs}}' "$1" 2>/dev/null | tail -n1
}

@test "onbox concurrent sessions: a short session exits without stopping a live longer session" {
	local bglog apid astatus sessions
	bglog="$BATS_TEST_TMPDIR/session-first.log"
	# first session: creates the container and stays live; the marker file in
	# the bind-mounted worktree proves its main exec is running
	{ run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo ready > .session-ready && sleep 30'; } >"$bglog" 2>&1 &
	apid=$!
	wait_for_session_marker "$PROJECT/.session-ready"
	sdrun podman inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null | grep -qx 'true'
	# second short session attaches to the running container and exits
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'true'
	[[ "$status" -eq 0 ]]
	# the container must still be running with the first session live
	sdrun podman inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null | grep -qx 'true'
	sessions="$(container_exec_sessions "$CTR")"
	[[ -n "$sessions" && "$sessions" != '[]' ]]
	# the last session's exit stops the container
	astatus=0
	wait "$apid" || astatus=$?
	[[ "$astatus" -eq 0 ]]
	wait_until_stopped "$CTR"
}

@test "onbox concurrent sessions: the container stops only after the last session exits when the short session starts it" {
	local bglog_first bglog_second apid_first apid_second astatus sessions
	bglog_first="$BATS_TEST_TMPDIR/session-short.log"
	bglog_second="$BATS_TEST_TMPDIR/session-long.log"
	# short session: creates and starts the container, stays live for a while;
	# its unit is held open past the session so its deactivation kill cannot
	# destroy the container it started
	{ run_onbox_session_holding_unit "$PROJECT" "$TALKBOX" 'sleep 8' 30 "$BATS_TEST_TMPDIR/session-short.status"; } >"$bglog_first" 2>&1 &
	apid_first=$!
	wait_for_container_e2e "$CTR"
	# long session attaches while the first is still live; the marker proves
	# its main exec is running before the short session's exec ends
	{ run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo ready > .session-ready && sleep 25'; } >"$bglog_second" 2>&1 &
	apid_second=$!
	wait_for_session_marker "$PROJECT/.session-ready"
	sdrun podman inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null | grep -qx 'true'
	# the starter's session has fully exited once its status file exists, so
	# its stop decision is complete; it must have been 0 and must not have
	# stopped the container while the other session is live
	wait_for_session_marker "$BATS_TEST_TMPDIR/session-short.status"
	[[ "$(cat "$BATS_TEST_TMPDIR/session-short.status")" == 0 ]]
	sdrun podman inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null | grep -qx 'true'
	sessions="$(container_exec_sessions "$CTR")"
	[[ -n "$sessions" && "$sessions" != '[]' ]]
	# the last (attaching) session's exit stops the container while the
	# starter's unit is still held alive, so only talkbox can have stopped it
	astatus=0
	wait "$apid_second" || astatus=$?
	[[ "$astatus" -eq 0 ]]
	wait_until_stopped "$CTR"
	# the held unit finishes with the short session's exit status
	astatus=0
	wait "$apid_first" || astatus=$?
	[[ "$astatus" -eq 0 ]]
}
