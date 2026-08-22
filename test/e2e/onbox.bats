load helpers

setup() {
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_BASE="$(basename "$PROJECT")"
}

teardown() {
	rm -rf "$PROJECT" "$TALKBOX"
}

@test "onbox starts a container whose working directory is /working/<project-base>" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'pwd'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"/working/$PROJECT_BASE"* ]]
}

@test "files written inside the container appear on the host worktree" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo written-in-container > from-container.txt'
	[[ "$status" -eq 0 ]]
	[[ -f "$PROJECT/from-container.txt" ]]
	[[ "$(cat "$PROJECT/from-container.txt")" == 'written-in-container' ]]
}

@test "onbox container has internet access" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'curl -fsS --max-time 15 https://example.com >/dev/null && echo ONLINE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'ONLINE'* ]]
}

@test "global dotfiles are copied into /home/dev" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'cat /home/dev/talkbox_marker'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-e2e-global-marker'* ]]
}

@test "project dotfiles override global dotfiles in /home/dev" {
	mkdir -p "$PROJECT/.dotfiles"
	printf 'project\n' >"$PROJECT/.dotfiles/conf.txt"
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'cat /home/dev/conf.txt'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'project'* ]]
}

@test "onbox symlink invocation starts a working session" {
	local bindir
	bindir="$(mktemp -d)"
	ln -s "$TALKBOX/talkbox.sh" "$bindir/onbox"
	# shellcheck disable=SC2016 # $0/$1 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/onbox" -c --noninteractive "pwd"' "$bindir" "$PROJECT"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"/working/$PROJECT_BASE"* ]]
	rm -rf "$bindir"
}

@test "onbox starts an interactive shell that exits via exit" {
	local exp
	exp="$(mktemp --suffix=.exp)"
	cat >"$exp" <<'EXPECT'
set timeout 90
set marker "SHELL_READY_[pid]"
cd [lindex $argv 0]
spawn "[lindex $argv 1]/talkbox.sh" onbox
send "echo $marker\r"
expect {
    "$marker" { }
    timeout { puts stderr "TIMEOUT waiting for interactive shell"; exit 1 }
    eof { puts stderr "EOF before interactive shell ready"; exit 1 }
}
send "exit\r"
expect eof
EXPECT
	run sdrun expect "$exp" "$PROJECT" "$TALKBOX"
	[[ "$status" -eq 0 ]]
	rm -f "$exp"
}
