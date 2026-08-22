PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

load_lib() {
	local lib="$1"
	if [[ ! -f "$PROJECT_ROOT/lib/$lib" ]]; then
		echo "lib/$lib is not implemented yet (see .llm/gen/plans/phase-1-onbox-minimal.gen.md)" >&2
		return 1
	fi
	source "$PROJECT_ROOT/lib/$lib"
}
