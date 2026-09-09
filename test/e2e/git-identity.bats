# shellcheck disable=SC2030,SC2031 # bats runs setup/test/teardown in one subshell
load helpers

setup() {
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"
	git -C "$PROJECT" commit -q --allow-empty -m host-initial
}

teardown() {
	teardown_talkbox "$PROJECT_SLUG"
	rm -rf "$PROJECT" "$TALKBOX"
}

@test "onbox container git identity matches the host user.name and user.email" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git config user.name && git config user.email'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test'* ]]
	[[ "$output" == *'test@example.com'* ]]
}

@test "onbox commits are attributed to the host git identity" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git commit --allow-empty -m identity-commit && git log --format="%an <%ae>" -1'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test <test@example.com>'* ]]
}

@test "netbox container git identity matches the host user.name and user.email" {
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'git config user.name && git config user.email'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test'* ]]
	[[ "$output" == *'test@example.com'* ]]
}

@test "netbox commits are attributed to the host git identity" {
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'git commit --allow-empty -m identity-commit && git log --format="%an <%ae>" -1'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test <test@example.com>'* ]]
}

@test "offbox container git identity matches the host user.name and user.email" {
	run run_talkbox "$PROJECT" "$TALKBOX" offbox -c --noninteractive 'git config user.name && git config user.email'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test'* ]]
	[[ "$output" == *'test@example.com'* ]]
}

@test "offbox commits are attributed to the host git identity" {
	run run_talkbox "$PROJECT" "$TALKBOX" offbox -c --noninteractive 'git commit --allow-empty -m identity-commit && git log --format="%an <%ae>" -1'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test <test@example.com>'* ]]
}

@test "a git command in a freshly started container runs only after setup.sh has run" {
	local shimdir log real
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	real="$(command -v podman)"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
exec '$real' "\$@"
EOF
	chmod +x "$shimdir/podman"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && PATH="$2:$PATH" "$0/talkbox.sh" onbox -c --noninteractive "git config user.name && git config user.email && git log --format=%s -1 && echo GIT-SUCCEEDED"' "$TALKBOX" "$PROJECT" "$shimdir"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test'* ]]
	[[ "$output" == *'test@example.com'* ]]
	[[ "$output" == *'GIT-SUCCEEDED'* ]]
	local setup_line cmd_line
	setup_line="$(grep -n 'exec.*setup\.sh' "$log" | head -n 1 | cut -d: -f1)"
	cmd_line="$(grep -n 'GIT-SUCCEEDED' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$setup_line" ]]
	[[ -n "$cmd_line" ]]
	[[ "$setup_line" -lt "$cmd_line" ]]
}
