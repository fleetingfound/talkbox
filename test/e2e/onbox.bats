load helpers

setup() {
	e2e_setup
	CTR="$ONBOX_CTR"
}

teardown() {
	e2e_teardown
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

@test "onbox container provides the setup.sh script" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'head -n 1 /usr/local/bin/setup.sh'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'#!/usr/bin/env bash'* ]]
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
	run run_talkbox_symlink "$PROJECT" "$bindir" onbox -c --noninteractive pwd
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"/working/$PROJECT_BASE"* ]]
	rm -rf "$bindir"
}

@test "onbox --command long form drives the container end-to-end" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --command --noninteractive pwd
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"/working/$PROJECT_BASE"* ]]
}

@test "onbox --gpu passes the GPU options to podman create on a GPU-less host" {
	local shimdir log
	log="$(mktemp)"
	shimdir="$(mk_podman_logging_shim "$log" start exec stop)"
	e2e_use_podman_shim "$shimdir"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --gpu -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nvidia.com/gpu=all' "$log")" -ge 1 ]]
	[[ "$(grep -c 'keep-groups' "$log")" -ge 1 ]]
	run sdrun podman container exists "$CTR"
	[[ "$status" -eq 0 ]]
	rm -rf "$shimdir" "$log"
}

@test "onbox auto-builds the base image when it is missing" {
	local id
	for id in $(sdrun podman ps -a --external --filter "ancestor=$E2E_BASE_IMAGE" --format '{{.ID}}'); do
		sdrun podman rm -f "$id" >/dev/null 2>&1 || true
	done
	run sdrun podman rmi "$E2E_BASE_IMAGE"
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists "$E2E_BASE_IMAGE"
	[[ "$status" -ne 0 ]]
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'true'
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists "$E2E_BASE_IMAGE"
	[[ "$status" -eq 0 ]]
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
