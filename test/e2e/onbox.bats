load helpers

setup() {
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_BASE="$(basename "$PROJECT")"
	CTR="$(onbox_ctr_name "$PROJECT")"
}

teardown() {
	sdrun podman rm -f -v "$CTR" >/dev/null 2>&1 || true
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
	if ! curl -fsS --max-time 10 https://example.com >/dev/null 2>&1; then
		skip "host has no internet connectivity; skipping the onbox internet test"
	fi
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'curl -fsS --max-time 15 https://example.com >/dev/null && echo ONLINE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'ONLINE'* ]]
}

@test "onbox dotfiles global bind-mount is read-only inside the container" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'touch /talkbox/dotfiles.global/probe'
	[[ "$status" -ne 0 ]]
}

@test "onbox dotfiles project bind-mount is read-only inside the container" {
	mkdir -p "$PROJECT/.dotfiles"
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'touch /talkbox/dotfiles.project/probe'
	[[ "$status" -ne 0 ]]
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

@test "onbox --command long form drives the container end-to-end" {
	# shellcheck disable=SC2016 # $0/$1 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox --command --noninteractive "pwd"' "$TALKBOX" "$PROJECT"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"/working/$PROJECT_BASE"* ]]
}

@test "onbox starts an interactive shell that exits via exit" {
	local exp
	exp="$(mktemp --suffix=.exp)"
	cat >"$exp" <<'EXPECT'
set timeout 30
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

@test "onbox -c --interactive runs a command and the session exits via exit" {
	local exp
	exp="$(mktemp --suffix=.exp)"
	cat >"$exp" <<'EXPECT'
set timeout 30
set marker "CMD_READY_[pid]"
cd [lindex $argv 0]
spawn "[lindex $argv 1]/talkbox.sh" onbox -c --interactive "echo $marker"
expect {
    "$marker" { }
    timeout { puts stderr "TIMEOUT waiting for interactive command output"; exit 1 }
    eof { puts stderr "EOF before interactive command output"; exit 1 }
}
send "exit\r"
expect eof
EXPECT
	run sdrun expect "$exp" "$PROJECT" "$TALKBOX"
	[[ "$status" -eq 0 ]]
	rm -f "$exp"
}
