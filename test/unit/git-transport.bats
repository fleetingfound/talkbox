# shellcheck shell=bash
# shellcheck disable=SC2016,SC2030,SC2031,SC2178,SC2317 # bats runs each test in a subshell; mocks redefine functions/namerefs; literal script text is asserted
load helpers

setup() {
	WORK="$BATS_TEST_TMPDIR/work"
	REMOTE="$BATS_TEST_TMPDIR/origin.git"
	git init -q --bare "$REMOTE"
	git init -q "$WORK"
	git -C "$WORK" config user.email test@example.com
	git -C "$WORK" config user.name talkbox-test
	BRANCH="$(git -C "$WORK" symbolic-ref --short HEAD)"
	printf 'base\n' >"$WORK/file.txt"
	git -C "$WORK" add file.txt
	git -C "$WORK" commit -q -m base
	git -C "$WORK" branch -q feature
	git -C "$WORK" remote add origin "$REMOTE"
	git -C "$WORK" push -q origin HEAD feature
	git -C "$WORK" fetch -q origin
}

@test "resolve_branches with --all and a remote enumerates the remote branches" {
	load_lib git.sh
	cd "$WORK"
	local -a expected=()
	mapfile -t expected < <(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin/)
	local -a got=()
	resolve_branches got yes '' origin
	[[ "${got[*]}" == "${expected[*]}" ]]
	[[ " ${got[*]} " == *' feature '* ]]
	[[ " ${got[*]} " == *' master '* ]]
}

@test "resolve_branches with --all and no remote enumerates the host branches" {
	load_lib git.sh
	cd "$WORK"
	local -a expected=()
	mapfile -t expected < <(git for-each-ref --format='%(refname:strip=2)' refs/heads/)
	local -a got=()
	resolve_branches got yes ''
	[[ "${got[*]}" == "${expected[*]}" ]]
	[[ " ${got[*]} " == *' feature '* ]]
}

@test "resolve_branches with a specified branch returns only that branch" {
	load_lib git.sh
	local -a got=()
	resolve_branches got no feature
	[[ "${#got[@]}" -eq 1 ]]
	[[ "${got[0]}" == 'feature' ]]
}

@test "resolve_branches without a branch defaults to the current branch" {
	load_lib git.sh
	cd "$WORK"
	local -a got=()
	resolve_branches got no ''
	[[ "${#got[@]}" -eq 1 ]]
	[[ "${got[0]}" == "$BRANCH" ]]
}

@test "sync_script emits the in-container sync script text" {
	load_lib git.sh
	run sync_script
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'source /talkbox/lib/merge.sh'* ]]
	[[ "$output" == *'git fetch host || exit 1'* ]]
	[[ "$output" == *'for b in "$@"; do custom_merge host "$b" || exit 1; done'* ]]
}

@test "container_sync_cmd assembles a podman exec command for a running container" {
	load_lib containers.sh
	local project="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$project"
	local base ctr script
	base="$(project_base "$project")"
	ctr="$(onbox_container_name "$project")"
	script='source /talkbox/lib/merge.sh'
	container_running() { return 0; }
	local -a cmd=()
	container_sync_cmd cmd "$project" onbox "$script" master feature
	[[ "${cmd[0]}" == podman ]]
	[[ "${cmd[1]}" == exec ]]
	[[ " ${cmd[*]} " == *" --workdir=/working/$base "* ]]
	[[ " ${cmd[*]} " == *" $ctr "* ]]
	[[ " ${cmd[*]} " == *" bash -c $script _ "* ]]
	[[ "${cmd[${#cmd[@]} - 2]}" == master ]]
	[[ "${cmd[${#cmd[@]} - 1]}" == feature ]]
}

@test "container_sync_cmd assembles a no-network temporary podman run for a stopped container" {
	load_lib containers.sh
	local project="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$project"
	local base resolved script
	base="$(project_base "$project")"
	resolved="$(readlink -f "$project")"
	script='source /talkbox/lib/merge.sh'
	container_running() { return 1; }
	local -a cmd=()
	container_sync_cmd cmd "$project" onbox "$script" master feature
	[[ "${cmd[0]}" == podman ]]
	[[ "${cmd[1]}" == run ]]
	[[ " ${cmd[*]} " == *' --rm --network=none '* ]]
	[[ " ${cmd[*]} " == *" --workdir=/working/$base "* ]]
	[[ " ${cmd[*]} " == *" --entrypoint=/bin/bash "* ]]
	[[ " ${cmd[*]} " == *" proj.onbox.gitdir:/working/$base/.git "* ]]
	[[ " ${cmd[*]} " == *" $resolved:/working/$base "* ]]
	[[ " ${cmd[*]} " == *" $resolved/.git:/host/git:ro "* ]]
	[[ " ${cmd[*]} " == *"/talkbox/lib/merge.sh:ro"* ]]
	[[ " ${cmd[*]} " == *" talkbox/base:latest "* ]]
	[[ " ${cmd[*]} " == *" -c $script _ "* ]]
	[[ "${cmd[${#cmd[@]} - 2]}" == master ]]
	[[ "${cmd[${#cmd[@]} - 1]}" == feature ]]
}

@test "plan_fetch fills separate bundle and fetch command arrays with no token leakage" {
	load_lib git.sh
	local project="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$project"
	local bundle="$BATS_TEST_TMPDIR/onbox.bundle"
	local -a bundle_cmd=() fetch_cmd=()
	plan_fetch bundle_cmd fetch_cmd "$project" onbox "$bundle"
	[[ " ${bundle_cmd[*]} " == *' podman run --rm --network=none '* ]]
	[[ " ${bundle_cmd[*]} " == *' git bundle create '* ]]
	[[ " ${bundle_cmd[*]} " == *' /host/bundle/onbox.bundle '* ]]
	[[ " ${fetch_cmd[*]} " == *' git fetch '* ]]
	[[ " ${fetch_cmd[*]} " == *" $bundle "* ]]
	[[ " ${fetch_cmd[*]} " == *' +refs/heads/*:refs/remotes/onbox/* '* ]]
	local tok
	for tok in "${fetch_cmd[@]}"; do
		[[ "$tok" == git || " ${bundle_cmd[*]} " != *" $tok "* ]]
	done
	for tok in "${bundle_cmd[@]}"; do
		[[ "$tok" == git || " ${fetch_cmd[*]} " != *" $tok "* ]]
	done
}

@test "run_sync_in_container delegates to container_sync_cmd and executes the result" {
	load_lib containers.sh
	local project="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$project"
	local script='source /talkbox/lib/merge.sh'
	local marker="$BATS_TEST_TMPDIR/executed"
	local captured=''
	container_sync_cmd() {
		local -n _out="$1"
		captured="project=$2 container=$3 script=$4 branches=${*:5}"
		_out=("touch" "$marker")
	}
	local status=0
	run_sync_in_container "$project" onbox "$script" master feature || status=$?
	[[ "$status" -eq 0 ]]
	[[ -e "$marker" ]]
	[[ "$captured" == *"project=$project"* ]]
	[[ "$captured" == *"container=onbox"* ]]
	[[ "$captured" == *"script=$script"* ]]
	[[ "$captured" == *'branches=master feature'* ]]
}
