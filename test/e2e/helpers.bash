PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

INDIVIDUAL_TEST_TIMEOUT="${INDIVIDUAL_TEST_TIMEOUT:-60}"
SD_TIMEOUT="${SD_TIMEOUT:-$((INDIVIDUAL_TEST_TIMEOUT - 5))}"
((SD_TIMEOUT > 0)) || SD_TIMEOUT=1

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
	# Empty the copied defaults/deny.ip and defaults/allow.ip so every e2e
	# onbox/netbox container starts from an empty effective deny set; the
	# deny/allow behaviour under test is exercised via CLI --deny-ip/--allow-ip
	# only.
	: >"$dest/defaults/read.mounts"
	: >"$dest/defaults/write.mounts"
	: >"$dest/defaults/ports"
	: >"$dest/defaults/deny.ip"
	: >"$dest/defaults/allow.ip"
	printf '%s\n' "$dest"
}

teardown_talkbox() {
	local slug="$1" extra v
	local ctrs=("$slug.onbox" "$slug.netbox" "$slug.offbox")
	shift
	for extra in "$@"; do
		if [[ -n "$extra" ]]; then
			ctrs+=("$extra")
		fi
	done
	sdrun podman rm -f -v "${ctrs[@]}" >/dev/null 2>&1 || true
	sdrun podman rmi "$slug.netbox.root" "$slug.offbox.root" >/dev/null 2>&1 || true
	for v in $(sdrun podman volume ls -q --filter "name=$slug" 2>/dev/null); do
		sdrun podman volume rm -f "$v" >/dev/null 2>&1 || true
	done
}

ensure_base_image_e2e() {
	local talkbox="$1"
	if ! sdrun podman image exists talkbox/base:latest >/dev/null 2>&1; then
		sdrun podman build -t talkbox/base:latest -f "$talkbox/image/Containerfile" "$talkbox/image" >/dev/null || return 1
	fi
	local id ids
	ids="$(sdrun podman ps -a --external --filter 'ancestor=talkbox/base:latest' --format '{{.ID}}')"
	for id in $ids; do
		sdrun podman rm -f "$id" >/dev/null 2>&1 || true
	done
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
	# $1 directory to serve, $2 nameref for PID, $3 nameref for port,
	# $4 optional bind address (default 127.0.0.1; use ::1 for an IPv6 server)
	local dir="$1"
	local -n pid_ref="$2"
	local -n port_ref="$3"
	local bind="${4:-127.0.0.1}"
	local out p n
	out="$(mktemp)"
	python3 "$PROJECT_ROOT/test/e2e/host_http_server.py" "$dir" "$bind" >"$out" 2>&1 &
	# shellcheck disable=SC2034 # nameref target consumed by the caller
	pid_ref=$!
	p=""
	for ((n = 0; n < 50; n++)); do
		p="$(head -n 1 "$out" 2>/dev/null)"
		[[ -n "$p" ]] && break
		sleep 0.1
	done
	rm -f "$out"
	# shellcheck disable=SC2034 # nameref target consumed by the caller
	port_ref="$p"
}

run_onbox_noninteractive() {
	local project="$1" talkbox="$2" cmd="$3"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox -c --noninteractive "$2"' "$talkbox" "$project" "$cmd"
}

run_talkbox() {
	local project="$1" talkbox="$2"
	shift 2
	# shellcheck disable=SC2016 # $1/$@ expand inside the wrapped bash -c
	sdrun bash -c 'cd "$1" && shift && exec "$@"' bash "$project" "$talkbox/talkbox.sh" "$@"
}

mk_gpu_shim() {
	# $1: log file path; prints the directory holding a podman shim which logs
	# every invocation to $1 and delegates to the real podman for everything
	# except start/exec/stop (stubbed to exit 0). A GPU-less host cannot start a
	# container carrying `--device nvidia.com/gpu=all` (the CDI device is
	# unresolvable), so the shim lets the `--gpu` flow reach `podman create`
	# and succeed while the create arguments are still observed in the log.
	local log="$1" dir real
	dir="$(mktemp -d)"
	real="$(command -v podman)"
	cat >"$dir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
case "\$1" in
start|exec|stop) exit 0 ;;
esac
exec '$real' "\$@"
EOF
	chmod +x "$dir/podman"
	printf '%s\n' "$dir"
}
