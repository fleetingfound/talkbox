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
	if [[ "$3" == '{{.State.Pid}}' ]]; then
		printf '12345\n'
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
exit 0
EOF
	chmod +x "$shimdir/podman"
}

# shellcheck disable=SC2154 # PODMAN_LOG is exported by the test using the shim
podman_line() {
	grep -m1 -- "$1" "$PODMAN_LOG" || true
}

# shellcheck disable=SC2154 # PODMAN_LOG is exported by the test using the shim
podman_line_no() {
	grep -n -m1 -- "$1" "$PODMAN_LOG" | cut -d: -f1
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
