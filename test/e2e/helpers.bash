PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

INDIVIDUAL_TEST_TIMEOUT="${INDIVIDUAL_TEST_TIMEOUT:-60}"
SD_TIMEOUT="${SD_TIMEOUT:-$((INDIVIDUAL_TEST_TIMEOUT - 5))}"
((SD_TIMEOUT > 0)) || SD_TIMEOUT=1

E2E_BASE_IMAGE='talkbox/base-e2e:latest'

sdrun() {
	systemd-run --user --wait --collect --pipe \
		-p "RuntimeMaxSec=$SD_TIMEOUT" \
		-p KillMode=control-group \
		-E "PATH=$PATH" \
		-E "TALKBOX_BASE_IMAGE=$E2E_BASE_IMAGE" \
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
	# Every test-reachable build path reads $TALKBOX_ROOT/image/Containerfile
	# (ensure_base_image, plan_rebuild, the netbox/offbox rebuild planners), so
	# swap in the minimal test image definition after the tree copy; the image/
	# context still provides setup.sh for the COPY.
	cp "$PROJECT_ROOT/image/Containerfile.minimal" "$dest/image/Containerfile"
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
	if ! sdrun podman image exists "$E2E_BASE_IMAGE" >/dev/null 2>&1; then
		sdrun podman build -t "$E2E_BASE_IMAGE" -f "$talkbox/image/Containerfile" "$talkbox/image" >/dev/null || return 1
	fi
	local id ids
	ids="$(sdrun podman ps -a --external --filter "ancestor=$E2E_BASE_IMAGE" --format '{{.ID}}')"
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

volume_mountpoint() {
	sdrun podman volume inspect --format '{{.Mountpoint}}' "$1" 2>/dev/null || true
}

container_stopped() {
	local state
	state="$(sdrun podman inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -x 'false' || true)"
	[[ "$state" == 'false' ]]
}

log_line_no() {
	grep -n -m1 -- "$1" "$2" | cut -d: -f1
}

E2E_EXTRA_DIRS=()
E2E_SERVER_PIDS=()
E2E_PODMAN_SHIM_DIR=''

e2e_register_dir() {
	E2E_EXTRA_DIRS+=("$1")
}

e2e_register_pid() {
	E2E_SERVER_PIDS+=("$1")
}

e2e_clear_pids() {
	E2E_SERVER_PIDS=()
}

e2e_use_podman_shim() {
	E2E_PODMAN_SHIM_DIR="$1"
}

e2e_setup() {
	E2E_EXTRA_DIRS=()
	E2E_SERVER_PIDS=()
	E2E_PODMAN_SHIM_DIR=''
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	ensure_base_image_e2e "$TALKBOX"
	# The standard derivations below (except PROJECT_SLUG, read back by
	# e2e_teardown) are consumed by the per-file setup() wrappers and test
	# bodies, which shellcheck cannot see.
	# shellcheck disable=SC2034 # consumed cross-file by the bats files
	PROJECT_BASE="$(basename "$PROJECT")"
	PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"
	# shellcheck disable=SC2034 # consumed cross-file by the bats files
	ONBOX_CTR="$(onbox_ctr_name "$PROJECT")"
	# shellcheck disable=SC2034 # consumed cross-file by the bats files
	NETBOX_CTR="$(netbox_ctr_name "$PROJECT")"
	# shellcheck disable=SC2034 # consumed cross-file by the bats files
	OFFBOX_CTR="$(offbox_ctr_name "$PROJECT")"
}

e2e_teardown() {
	# Safe against a half-created fixture: bats still invokes teardown() after
	# a failed setup(), so every variable is guarded before any rm -rf and
	# missing resources are tolerated.
	local pid dir
	for pid in "${E2E_SERVER_PIDS[@]}"; do
		if [[ -n "$pid" ]]; then
			kill "$pid" 2>/dev/null || true
		fi
	done
	if [[ -n "${PROJECT_SLUG:-}" ]]; then
		teardown_talkbox "$PROJECT_SLUG" "$@"
	fi
	for dir in "${PROJECT:-}" "${TALKBOX:-}" "${E2E_EXTRA_DIRS[@]}"; do
		if [[ -n "$dir" ]]; then
			rm -rf "$dir"
		fi
	done
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

wait_for_http() {
	local url="$1" n
	for ((n = 0; n < 20; n++)); do
		if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.5
	done
	return 1
}

run_onbox_noninteractive() {
	local project="$1" talkbox="$2" cmd="$3"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox -c --noninteractive "$2"' "$talkbox" "$project" "$cmd"
}

run_talkbox() {
	# <project> <talkbox> [args…]; when e2e_use_podman_shim has registered a
	# shim directory, PATH="$shimdir:$PATH" is prepended for the wrapped
	# talkbox invocation so its podman calls reach the shim.
	local project="$1" talkbox="$2"
	shift 2
	local -a env_args=()
	if [[ -n "$E2E_PODMAN_SHIM_DIR" ]]; then
		env_args=("PATH=$E2E_PODMAN_SHIM_DIR:$PATH")
	fi
	# shellcheck disable=SC2016 # $1/$@ expand inside the wrapped bash -c
	sdrun env "${env_args[@]}" bash -c 'cd "$1" && shift && exec "$@"' bash "$project" "$talkbox/talkbox.sh" "$@"
}

run_talkbox_symlink() {
	# <project> <bindir> <name> [args…]; invokes <bindir>/<name> (a symlink to
	# talkbox.sh under a differently-named executable) from the project dir.
	local project="$1" bin="$2" name="$3"
	shift 3
	# shellcheck disable=SC2016 # $1/$@ expand inside the wrapped bash -c
	sdrun bash -c 'cd "$1" && shift && exec "$@"' bash "$project" "$bin/$name" "$@"
}

mk_podman_logging_shim() {
	# $1: log file path; remaining arguments name the podman subcommands the
	# shim stubs to exit 0. Every podman invocation is appended to the log and
	# then delegated to the real podman; the directory holding the shim is
	# printed for PATH-prepending via e2e_use_podman_shim. Stubbing
	# start/exec/stop lets a GPU-less host reach `podman create` for a --gpu
	# container whose CDI device is unresolvable at start time. This e2e
	# delegate is independent of the unit-side mock factory: delegation to the
	# real podman never appears in make_podman_shim.
	local log="$1" dir real sub stubs
	shift
	dir="$(mktemp -d)"
	real="$(command -v podman)"
	stubs=''
	for sub in "$@"; do
		stubs+="$sub|"
	done
	stubs="${stubs%|}"
	cat >"$dir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
EOF
	if [[ -n "$stubs" ]]; then
		cat >>"$dir/podman" <<EOF
case "\$1" in
$stubs) exit 0 ;;
esac
EOF
	fi
	cat >>"$dir/podman" <<EOF
exec '$real' "\$@"
EOF
	chmod +x "$dir/podman"
	printf '%s\n' "$dir"
}
