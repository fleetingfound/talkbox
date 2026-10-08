load helpers

setup() {
	e2e_setup
	git -C "$PROJECT" commit -q --allow-empty -m host-initial
}

teardown() {
	e2e_teardown
}

@test "onbox, netbox and offbox container git identity matches the host user.name and user.email" {
	local c
	for c in onbox netbox offbox; do
		run run_talkbox "$PROJECT" "$TALKBOX" "$c" -c --noninteractive 'git config user.name && git config user.email'
		[[ "$status" -eq 0 ]]
		[[ "$output" == *'talkbox-test'* ]]
		[[ "$output" == *'test@example.com'* ]]
	done
}

@test "onbox, netbox and offbox commits are attributed to the host git identity" {
	local c
	for c in onbox netbox offbox; do
		run run_talkbox "$PROJECT" "$TALKBOX" "$c" -c --noninteractive 'git commit --allow-empty -m identity-commit && git log --format="%an <%ae>" -1'
		[[ "$status" -eq 0 ]]
		[[ "$output" == *'talkbox-test <test@example.com>'* ]]
	done
}

@test "a git command in a freshly started container runs only after setup.sh has run" {
	local shimdir log
	log="$BATS_TEST_TMPDIR/podman.log"
	shimdir="$(mk_podman_logging_shim "$log")"
	e2e_register_dir "$shimdir"
	e2e_use_podman_shim "$shimdir"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive "git config user.name && git config user.email && git log --format=%s -1 && echo GIT-SUCCEEDED"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test'* ]]
	[[ "$output" == *'test@example.com'* ]]
	[[ "$output" == *'GIT-SUCCEEDED'* ]]
	local setup_line cmd_line
	setup_line="$(log_line_no 'exec.*setup\.sh' "$log")"
	cmd_line="$(log_line_no 'GIT-SUCCEEDED' "$log")"
	[[ -n "$setup_line" ]]
	[[ -n "$cmd_line" ]]
	[[ "$setup_line" -lt "$cmd_line" ]]
}
