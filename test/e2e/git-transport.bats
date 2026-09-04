# shellcheck disable=SC2030,SC2031 # bats runs setup/test/teardown in one subshell; EXTRA_DIRS is read back in teardown
load helpers

setup() {
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"
	ONBOX_CTR="$PROJECT_SLUG.onbox"
	NETBOX_CTR="$PROJECT_SLUG.netbox"
	OFFBOX_CTR="$PROJECT_SLUG.offbox"
	PLAIN_CTR=""
	EXTRA_DIRS=()
	BRANCH="$(git -C "$PROJECT" symbolic-ref --short HEAD)"
	GITDIR_VOL="$PROJECT_SLUG.onbox.gitdir"
	git -C "$PROJECT" commit -q --allow-empty -m host-initial
}

teardown() {
	teardown_talkbox "$PROJECT_SLUG" "$PLAIN_CTR"
	rm -rf "$PROJECT" "$TALKBOX" "${EXTRA_DIRS[@]}"
}

volume_mountpoint() {
	sdrun podman volume inspect --format '{{.Mountpoint}}' "$1" 2>/dev/null || true
}

@test "onbox exposes the host git history as the host remote inside the container" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git remote get-url host'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'/host/git'* ]]
}

@test "onbox gitdir volume is a fresh git directory wired to the host remote, not a copy of the host git dir" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'true'
	[[ "$status" -eq 0 ]]
	local mp
	mp="$(volume_mountpoint "$GITDIR_VOL")"
	[[ -n "$mp" ]]
	[[ -d "$mp/objects" ]]
	[[ -d "$mp/refs" ]]
	[[ -f "$mp/HEAD" ]]
	grep -q '\[remote "host"\]' "$mp/config"
	grep -q '/host/git' "$mp/config"
	if grep -q 'test@example.com' "$mp/config"; then
		return 1
	fi
}

@test "the onbox container working tree is connected to the host history via the initial fetch" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git log --oneline'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'host-initial'* ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'grep -q "\[remote \"host\"\]" .git/config && echo CONNECTED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'CONNECTED'* ]]
}

@test "a commit made in the container is visible in the container gitdir volume" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git config user.email c@example.com && git config user.name container && git commit --allow-empty -m container-commit'
	[[ "$status" -eq 0 ]]
	local mp host_head vol_head
	mp="$(volume_mountpoint "$GITDIR_VOL")"
	[[ -n "$mp" ]]
	host_head="$(git -C "$PROJECT" rev-parse HEAD)"
	vol_head="$(cat "$mp/refs/heads/$BRANCH")"
	[[ -n "$vol_head" ]]
	[[ "$vol_head" != "$host_head" ]]
}

@test "onbox adds git mounts for a git-tracked project but not for a non-git folder" {
	local plain
	plain="$(mktemp -d)"
	EXTRA_DIRS+=("$plain")
	PLAIN_CTR="$(project_slug_e2e "$plain").onbox"
	run run_talkbox "$plain" "$TALKBOX" onbox -c --noninteractive 'test ! -e /host/git && echo NO_GIT'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'NO_GIT'* ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'test -d /host/git && echo GIT'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'GIT'* ]]
}

@test "onbox, netbox and offbox refuse when the project .git points outside the project" {
	local outside
	outside="$(mktemp -d)"
	EXTRA_DIRS+=("$outside")
	mkdir -p "$outside/.git"
	rm -rf "$PROJECT/.git"
	printf 'gitdir: %s/.git\n' "$outside" >"$PROJECT/.git"
	local c
	for c in onbox netbox offbox; do
		run run_talkbox "$PROJECT" "$TALKBOX" "$c" -c --noninteractive 'true'
		[[ "$status" -ne 0 ]]
		[[ "$output" == *'talkbox:'* ]]
	done
	for c in "$ONBOX_CTR" "$NETBOX_CTR" "$OFFBOX_CTR"; do
		run sdrun podman container exists "$c"
		[[ "$status" -ne 0 ]]
	done
}

@test "git operations inside a submodule are blocked within the container" {
	local remote
	remote="$(mktemp -d)"
	EXTRA_DIRS+=("$remote")
	git -C "$remote" init -q
	git -C "$remote" config user.email t@example.com
	git -C "$remote" config user.name talkbox-test
	printf 'submodule-file\n' >"$remote/file.txt"
	git -C "$remote" add .
	git -C "$remote" commit -q -m submodule-initial
	git -C "$PROJECT" -c protocol.file.allow=always submodule add -q "$remote" sub
	git -C "$PROJECT" commit -q -m add-submodule
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git -C sub status'
	[[ "$status" -ne 0 ]]
}

@test "onbox fetch brings a container commit into the host repo via a bundle without transferring configs or hooks" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git config user.email c@example.com && git config user.name container-user && git commit --allow-empty -m container-commit'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'printf "#!/bin/sh\necho hook\n" > .git/hooks/container-hook && chmod +x .git/hooks/container-hook'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	run git -C "$PROJECT" log --oneline "refs/remotes/onbox/$BRANCH"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'container-commit'* ]]
	[[ "$(git -C "$PROJECT" config user.email)" == 'test@example.com' ]]
	if grep -q 'container-user' "$PROJECT/.git/config"; then
		return 1
	fi
	if [[ -e "$PROJECT/.git/hooks/container-hook" ]]; then
		return 1
	fi
}

@test "onbox fetch --all fetches from the onbox, netbox and offbox git histories" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git config user.email o@example.com && git config user.name onbox-user && git commit --allow-empty -m onbox-commit'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'git config user.email n@example.com && git config user.name netbox-user && git commit --allow-empty -m netbox-commit'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" offbox -c --noninteractive 'git config user.email f@example.com && git config user.name offbox-user && git commit --allow-empty -m offbox-commit'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch --all
	[[ "$status" -eq 0 ]]
	run git -C "$PROJECT" log --oneline "refs/remotes/onbox/$BRANCH"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'onbox-commit'* ]]
	run git -C "$PROJECT" log --oneline "refs/remotes/netbox/$BRANCH"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'netbox-commit'* ]]
	run git -C "$PROJECT" log --oneline "refs/remotes/offbox/$BRANCH"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'offbox-commit'* ]]
}
