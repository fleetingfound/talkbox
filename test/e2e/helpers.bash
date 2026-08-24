PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

INDIVIDUAL_TEST_TIMEOUT="${INDIVIDUAL_TEST_TIMEOUT:-60}"
SD_TIMEOUT="${SD_TIMEOUT:-$((INDIVIDUAL_TEST_TIMEOUT - 5))}"
(( SD_TIMEOUT > 0 )) || SD_TIMEOUT=1

sdrun() {
	systemd-run --user --wait --collect --pipe \
		-p "RuntimeMaxSec=$SD_TIMEOUT" \
		-p KillMode=control-group \
		-E "PATH=$PATH" \
		-- "$@"
}

mk_project() {
	local dir
	dir="$(mktemp -d)"
	git -C "$dir" init -q
	git -C "$dir" config user.email test@example.com
	git -C "$dir" config user.name talkbox-test
	printf '%s\n' "$dir"
}

mk_talkbox() {
	local dest item
	dest="$(mktemp -d)"
	for item in talkbox.sh lib image defaults; do
		if [[ -e "$PROJECT_ROOT/$item" ]]; then
			cp -a "$PROJECT_ROOT/$item" "$dest/$item"
		fi
	done
	chmod +x "$dest/talkbox.sh" 2>/dev/null || true
	mkdir -p "$dest/defaults/dotfiles"
	printf 'talkbox-e2e-global-marker\n' >"$dest/defaults/dotfiles/talkbox_marker"
	printf 'global\n' >"$dest/defaults/dotfiles/conf.txt"
	# Neutralise the copied default mounts/ports so e2e is hermetic: default
	# mounts would otherwise reference host paths outside the test and are
	# covered by unit tests; e2e exercises only the CLI --read/--write/--port.
	: >"$dest/defaults/read.mounts"
	: >"$dest/defaults/write.mounts"
	: >"$dest/defaults/ports"
	printf '%s\n' "$dest"
}

project_slug_e2e() {
	local base
	base="$(basename "$1")"
	base="${base,,}"
	base="${base//[^a-z0-9]/-}"
	while [[ "$base" == *--* ]]; do
		base="${base//--/-}"
	done
	base="${base#-}"
	base="${base%-}"
	printf '%s\n' "$base"
}

onbox_ctr_name() {
	printf '%s\n' "$(project_slug_e2e "$1").onbox"
}

netbox_ctr_name() {
	printf '%s\n' "$(project_slug_e2e "$1").netbox"
}

offbox_ctr_name() {
	printf '%s\n' "$(project_slug_e2e "$1").offbox"
}

start_host_http_server() {
	# $1 directory to serve, $2 nameref for PID, $3 nameref for port
	local dir="$1"
	local -n pid_ref="$2"
	local -n port_ref="$3"
	local out p n
	out="$(mktemp)"
	python3 "$PROJECT_ROOT/test/e2e/host_http_server.py" "$dir" >"$out" 2>&1 &
	pid_ref=$!
	p=""
	for ((n = 0; n < 50; n++)); do
		p="$(head -n 1 "$out" 2>/dev/null)"
		[[ -n "$p" ]] && break
		sleep 0.1
	done
	rm -f "$out"
	port_ref="$p"
}

run_onbox_noninteractive() {
	local project="$1" talkbox="$2" cmd="$3"
	sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox -c --noninteractive "$2"' "$talkbox" "$project" "$cmd"
}

run_talkbox() {
	local project="$1" talkbox="$2"
	shift 2
	sdrun bash -c 'cd "$1" && shift && exec "$@"' bash "$project" "$talkbox/talkbox.sh" "$@"
}
