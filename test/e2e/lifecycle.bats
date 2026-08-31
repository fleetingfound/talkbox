load helpers

setup() {
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_BASE="$(basename "$PROJECT")"
	PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"
	CTR="$PROJECT_SLUG.onbox"
	HOST_SRV_PID=""
}

teardown() {
	if [[ -n "$HOST_SRV_PID" ]]; then
		kill "$HOST_SRV_PID" 2>/dev/null || true
	fi
	sdrun podman rm -f -v "$CTR" >/dev/null 2>&1 || true
	local v
	for v in $(sdrun podman volume ls -q --filter "name=$PROJECT_SLUG" 2>/dev/null); do
		sdrun podman volume rm -f "$v" >/dev/null 2>&1 || true
	done
	rm -rf "$PROJECT" "$TALKBOX"
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
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox --read "$2" -c --noninteractive "cat /host/read/$(basename "$2")"' "$TALKBOX" "$PROJECT" "$src"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'mountable-config'* ]]
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox --read "$2" -c --noninteractive "touch /host/read/$(basename "$2")"' "$TALKBOX" "$PROJECT" "$src"
	[[ "$status" -ne 0 ]]
	rm -f "$src"
}

@test "onbox --write exposes a writable mount inside the container" {
	local data
	data="$(mktemp -d)"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox --write "$2" -c --noninteractive "echo written > /host/write/$(basename "$2")/out.txt"' "$TALKBOX" "$PROJECT" "$data"
	[[ "$status" -eq 0 ]]
	[[ -f "$data/out.txt" ]]
	[[ "$(cat "$data/out.txt")" == 'written' ]]
	rm -rf "$data"
}

@test "onbox --port makes a host port reachable inside the container" {
	command -v python3 >/dev/null 2>&1 || skip "python3 is required for the port e2e test"
	local port www srv n
	www="$(mktemp -d)"
	printf 'port-marker\n' >"$www/marker"
	start_host_http_server "$www" srv port
	HOST_SRV_PID=$srv
	for ((n = 0; n < 20; n++)); do
		if curl -fsS --max-time 2 "http://127.0.0.1:$port/marker" >/dev/null 2>&1; then
			break
		fi
		sleep 0.5
	done
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox --port "$2" -c --noninteractive "curl -fsS --max-time 10 http://127.0.0.1:$2/marker"' "$TALKBOX" "$PROJECT" "$port"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'port-marker'* ]]
	kill "$srv" 2>/dev/null || true
	HOST_SRV_PID=""
	rm -rf "$www"
}

@test "onbox --rm-container removes the persistent container and its gitdir named volume" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'true'
	[[ "$status" -eq 0 ]]
	run sdrun podman container exists "$CTR"
	[[ "$status" -eq 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.onbox.gitdir"
	[[ "$status" -eq 0 ]]
	# shellcheck disable=SC2016 # $0/$1 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox --rm-container' "$TALKBOX" "$PROJECT"
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
	# shellcheck disable=SC2016 # $0/$1 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox --recontain' "$TALKBOX" "$PROJECT"
	[[ "$status" -eq 0 ]]
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'test ! -e /tmp/talkbox-recontain-probe && (git log --oneline | grep -q container-commit && echo STALE || echo FRESH)'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'FRESH'* ]]
}

@test "onbox --rebuild rebuilds the base image and starts the container" {
	# shellcheck disable=SC2016 # $0/$1 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox --rebuild' "$TALKBOX" "$PROJECT"
	[[ "$status" -eq 0 ]]
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'pwd'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"/working/$PROJECT_BASE"* ]]
}
