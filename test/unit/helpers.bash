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
