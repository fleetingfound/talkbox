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
#   PODMAN_INSPECT_MOUNTS  names printed for an inspect over container Mounts
#   PODMAN_INSPECT_RC, PODMAN_INSPECT_STDERR  make inspect fail
#   PODMAN_UNSHARE_RC, PODMAN_UNSHARE_STDERR  make unshare fail
#   PODMAN_UNSHARE_LOG  file receiving one PATH= line per unshare invocation
#   PODMAN_EXEC_SESSIONS  live exec sessions of the container (one row each for
#     `exec list`, a JSON array for an inspect over a .ExecIDs format)
#   PODMAN_EXEC_SESSIONS_RC, PODMAN_EXEC_SESSIONS_STDERR  make the
#     exec-session listing fail (unsupported subcommand / listing error)
#   PODMAN_STALL_PATTERN, PODMAN_STALL_SECONDS  make matching invocations
#     sleep before responding; PODMAN_STALL_HOOK is an optional script run
#     with the full invocation as $1 when a stall fires, so a test can probe
#     external state (e.g. a lock file) from inside the stalled invocation.
#     The shim itself stays oblivious to any locking.
cat >/dev/null 2>&1 || true
printf '%s\n' "$*" >>"$PODMAN_LOG"
if [[ -n "${PODMAN_STALL_PATTERN:-}" && "$*" == *"$PODMAN_STALL_PATTERN"* ]]; then
	if [[ -n "${PODMAN_STALL_HOOK:-}" ]]; then
		bash "$PODMAN_STALL_HOOK" "$*" || true
	fi
	sleep "${PODMAN_STALL_SECONDS:-0}"
fi
if [[ -n "${PODMAN_FAIL_PATTERN:-}" && "$*" == *"$PODMAN_FAIL_PATTERN"* ]]; then
	exit "${PODMAN_FAIL_CODE:-1}"
fi
if [[ "$*" == *ExecIDs* ]] || [[ "$1 $2" == 'exec list' ]]; then
	if [[ -n "${PODMAN_EXEC_SESSIONS_RC:-}" && "${PODMAN_EXEC_SESSIONS_RC}" != 0 ]]; then
		printf '%s\n' "${PODMAN_EXEC_SESSIONS_STDERR:-podman exec list: unsupported subcommand}" >&2
		exit "${PODMAN_EXEC_SESSIONS_RC}"
	fi
	if [[ "$1" == exec ]]; then
		for session in ${PODMAN_EXEC_SESSIONS:-}; do
			printf '%s\n' "$session"
		done
	else
		out='['
		sep=''
		for session in ${PODMAN_EXEC_SESSIONS:-}; do
			out+="$sep\"$session\""
			sep=','
		done
		printf '%s]\n' "$out"
	fi
	exit 0
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
if [[ "$1" == inspect && ("$2" == -f || "$2" == --format) ]]; then
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
	elif [[ "$3" == *'{{range .Mounts}}'* ]]; then
		for mnt in ${PODMAN_INSPECT_MOUNTS:-}; do
			printf '%s ' "$mnt"
		done
		printf '\n'
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

# Line number of the exec-session listing invocation for a container in the
# podman log, matching either `podman exec list <ctr>` or an inspect over a
# .ExecIDs format; prints nothing when the listing was never invoked.
# shellcheck disable=SC2154 # PODMAN_LOG is exported by the test using the shim
podman_session_line_no() {
	local ctr="$1" match
	match="$(grep -n -E 'ExecIDs|exec list' "$PODMAN_LOG" | grep -m1 -- "$ctr")" || true
	[[ -n "$match" ]] && printf '%s\n' "${match%%:*}"
	return 0
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

grep_count() {
	grep -c -- "$1" "$2" || true
}

# Writes a probe hook for the podman shim's stall feature. The shim runs the
# hook with a stalled podman invocation as $1; the hook records whether the
# lock at $LOCK_PROBE_PATH is held or free, as "held|free <invocation>", to
# $LOCK_PROBE_LOG. A missing lock file means no lock was ever taken (free);
# otherwise a nonblocking exclusive flock in the probe's own open file
# description decides, without disturbing the holder.
make_lock_probe_hook() {
	local hook="$1"
	cat >"$hook" <<'EOF'
#!/usr/bin/env bash
if [[ ! -e "$LOCK_PROBE_PATH" ]] || flock -n -x "$LOCK_PROBE_PATH" true 2>/dev/null; then
	state=free
else
	state=held
fi
printf '%s %s\n' "$state" "$1" >>"$LOCK_PROBE_LOG"
EOF
}

# Succeeds when the lock at $1 is not held: a missing lock file means no lock
# was ever taken, an existing one must be acquirable non-blockingly.
lock_is_free() {
	local path="$1"
	if [[ -e "$path" ]]; then
		flock -n -x "$path" true 2>/dev/null
	fi
}
