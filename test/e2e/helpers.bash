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
	printf '%s\n' "$dest"
}

run_onbox_noninteractive() {
	local project="$1" talkbox="$2" cmd="$3"
	sdrun bash -c 'cd "$1" && "$0/talkbox.sh" onbox -c --noninteractive "$2"' "$talkbox" "$project" "$cmd"
}
