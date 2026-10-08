PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

load_lib() {
	local lib="$1"
	if [[ ! -f "$PROJECT_ROOT/lib/$lib" ]]; then
		echo "lib/$lib does not exist" >&2
		return 1
	fi
	# shellcheck disable=SC1090 # the sourced lib path is dynamic
	source "$PROJECT_ROOT/lib/$lib"
}

# Sourced from bats tests via `load helpers`; the container libraries must be
# loaded after the file scope (load_lib sources into the test's shell), hence
# this helper instead of a top-level source.
load_container_libs() {
	load_lib naming.sh
	load_lib mounts.sh
	load_lib network.sh
	load_lib containers.sh
}

make_podman_shim() {
	local shimdir="$1"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<'EOF'
#!/usr/bin/env bash
# logging podman mock; behaviour is driven by the PODMAN_* environment:
#   PODMAN_LOG         file receiving one line per invocation
#   PODMAN_CONTAINERS  names of existing containers
#   PODMAN_VOLUMES     names of existing volumes
#   PODMAN_IMAGES      names of existing images
#   PODMAN_RUNNING     names of running containers
#   PODMAN_PS_NAMES    names listed for ancestor-filtered ps
#   PODMAN_EXTERNAL    IDs listed for external ancestor-filtered ps
#   PODMAN_FAIL_PATTERN, PODMAN_FAIL_CODE  make matching invocations fail
#   PODMAN_INSPECT_PID  PID printed for inspect -f {{.State.Pid}} (default 12345)
#   PODMAN_INSPECT_RC, PODMAN_INSPECT_STDERR  make inspect fail
#   PODMAN_UNSHARE_RC, PODMAN_UNSHARE_STDERR  make unshare fail
#   PODMAN_UNSHARE_LOG  file receiving one PATH= line per unshare invocation
cat >/dev/null 2>&1 || true
printf '%s\n' "$*" >>"$PODMAN_LOG"
if [[ -n "${PODMAN_FAIL_PATTERN:-}" && "$*" == *"$PODMAN_FAIL_PATTERN"* ]]; then
	exit "${PODMAN_FAIL_CODE:-1}"
fi
if [[ "$1 $2" == 'container exists' ]]; then
	for ctr in $PODMAN_CONTAINERS; do
		[[ "$ctr" == "$3" ]] && exit 0
	done
	exit 1
fi
if [[ "$1 $2" == 'volume exists' ]]; then
	for vol in $PODMAN_VOLUMES; do
		[[ "$vol" == "$3" ]] && exit 0
	done
	exit 1
fi
if [[ "$1 $2" == 'image exists' ]]; then
	for img in $PODMAN_IMAGES; do
		[[ "$img" == "$3" ]] && exit 0
	done
	exit 1
fi
if [[ "$1 $2" == 'inspect -f' ]]; then
	if [[ -n "${PODMAN_INSPECT_RC:-}" && "${PODMAN_INSPECT_RC}" != 0 ]]; then
		printf '%s\n' "${PODMAN_INSPECT_STDERR:-podman inspect: container not found}" >&2
		exit "${PODMAN_INSPECT_RC}"
	fi
	if [[ "$3" == '{{.State.Pid}}' ]]; then
		printf '%s\n' "${PODMAN_INSPECT_PID:-12345}"
	elif [[ "$3" == '{{.State.Running}}' ]]; then
		for ctr in $PODMAN_RUNNING; do
			[[ "$ctr" == "$4" ]] && {
				printf 'true\n'
				exit 0
			}
		done
		printf 'false\n'
	fi
	exit 0
fi
if [[ "$1 $2" == 'ps -a' ]]; then
	if [[ "$*" == *' --external'* ]]; then
		for id in $PODMAN_EXTERNAL; do
			printf '%s\n' "$id"
		done
	else
		for name in $PODMAN_PS_NAMES; do
			printf '%s\n' "$name"
		done
	fi
	exit 0
fi
if [[ "$1" == 'unshare' ]]; then
	if [[ -n "${PODMAN_UNSHARE_LOG:-}" ]]; then
		printf 'PATH=%s\n' "$PATH" >>"$PODMAN_UNSHARE_LOG"
	fi
	if [[ -n "${PODMAN_UNSHARE_RC:-}" && "${PODMAN_UNSHARE_RC}" != 0 ]]; then
		printf '%s\n' "${PODMAN_UNSHARE_STDERR:-nft: netlink error: Operation not permitted}" >&2
		exit "${PODMAN_UNSHARE_RC}"
	fi
	exit 0
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
}

# Standard shim activation shared by the unit bats files: shim on PATH,
# PODMAN_LOG exported and PODMAN_IMAGES seeded with the base image. An optional
# explicit image argument replaces the base_image_name derivation for tests
# which cannot source lib/naming.sh (the dispatcher tests drive talkbox.sh as a
# subprocess).
# shellcheck disable=SC2154 # SHIM and LOG are initialised by the test setup
use_podman_shim() {
	make_podman_shim "$SHIM"
	PATH="$SHIM:$PATH"
	export PODMAN_LOG="$LOG"
	if (($#)); then
		PODMAN_IMAGES="$1"
	else
		PODMAN_IMAGES="$(base_image_name)"
	fi
	export PODMAN_IMAGES
}

# shellcheck disable=SC2154 # PODMAN_LOG is exported by the test using the shim
podman_line() {
	grep -m1 -- "$1" "$PODMAN_LOG" || true
}

log_line_no() {
	grep -n -m1 -- "$1" "$2" | cut -d: -f1
}

# shellcheck disable=SC2154 # PODMAN_LOG is exported by the test using the shim
podman_line_no() {
	log_line_no "$1" "$PODMAN_LOG"
}

# shellcheck disable=SC2154 # PODMAN_LOG is exported by the test using the shim
podman_count() {
	grep -c -- "$1" "$PODMAN_LOG" || true
}

# shellcheck disable=SC2154 # PODMAN_LOG is exported by the test using the shim
podman_create_line() {
	grep -m1 '^create ' "$PODMAN_LOG" || true
}

line_has_token() {
	local line="$1" token="$2" element
	for element in $line; do
		[[ "$element" == "$token" ]] && return 0
	done
	return 1
}

line_lacks_token() {
	if line_has_token "$1" "$2"; then
		return 1
	fi
	return 0
}

line_token_at() {
	local line="$1" token="$2" i=0 element
	for element in $line; do
		((i += 1))
		[[ "$element" == "$token" ]] && {
			printf '%s\n' "$i"
			return 0
		}
	done
	printf '0\n'
}

plan_subcommands() {
	local -n _plan="$1"
	local i
	for ((i = 0; i < ${#_plan[@]}; i++)); do
		if [[ "${_plan[$i]}" == podman ]]; then
			printf '%s\n' "${_plan[$((i + 1))]}"
		fi
	done
}

array_contains() {
	local value="$1"
	shift
	local element
	for element in "$@"; do
		if [[ "$element" == "$value" ]]; then
			return 0
		fi
	done
	return 1
}

array_has_none() {
	local needle="$1"
	shift
	local element
	for element in "$@"; do
		if [[ "$element" == *"$needle"* ]]; then
			return 1
		fi
	done
	return 0
}
