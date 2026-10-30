# shellcheck shell=bash

TALKBOX_LOCK_FD=""

talkbox_lock_dir() {
	if [[ -n "${TALKBOX_LOCK_DIR:-}" ]]; then
		printf '%s\n' "$TALKBOX_LOCK_DIR"
	elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
		printf '%s\n' "$XDG_RUNTIME_DIR/talkbox/locks"
	else
		printf '%s\n' "${TMPDIR:-/tmp}/talkbox-locks-$(id -u)"
	fi
}

container_lock_path() {
	printf '%s/%s\n' "$(talkbox_lock_dir)" "$1"
}

acquire_container_lock() {
	local path
	path="$(container_lock_path "$1")"
	mkdir -p "${path%/*}"
	exec {TALKBOX_LOCK_FD}>"$path"
	flock -x "$TALKBOX_LOCK_FD"
}

release_container_lock() {
	if [[ -n "${TALKBOX_LOCK_FD:-}" ]]; then
		exec {TALKBOX_LOCK_FD}>&-
		TALKBOX_LOCK_FD=""
	fi
}

run_without_lock_fd() {
	if [[ -n "${TALKBOX_LOCK_FD:-}" ]]; then
		(
			exec {TALKBOX_LOCK_FD}>&-
			"$@"
		)
	else
		"$@"
	fi
}
