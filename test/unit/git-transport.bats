# shellcheck shell=bash
# shellcheck disable=SC2016,SC2030,SC2031,SC2178,SC2317 # bats runs each test in a subshell; mocks redefine functions/namerefs; literal script text is asserted
load helpers

setup() {
	load_lib naming.sh
	WORK="$BATS_TEST_TMPDIR/work"
	REMOTE="$BATS_TEST_TMPDIR/origin.git"
	LOG="$BATS_TEST_TMPDIR/podman.log"
	PODMAN_LOG="$LOG"
	VOL="$(gitdir_volume "$WORK" onbox)"
	CTR_REPO="$BATS_TEST_TMPDIR/ctr-repo"
	declare -gA PODMAN_MOUNTPOINTS=()
	PODMAN_VOLUMES=""
	PODMAN_FAIL_PATTERN=""
	PODMAN_FAIL_CODE=""
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
	git clone -q "$WORK" "$CTR_REPO"
	git -C "$CTR_REPO" config user.email ctr@example.com
	git -C "$CTR_REPO" config user.name ctr-user
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
	[[ " ${got[*]} " == *" $BRANCH "* ]]
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
	[[ " ${cmd[*]} " == *" proj.onbox.gitdir:/working/$base/.git "* ]]
	[[ " ${cmd[*]} " == *" $resolved:/working/$base "* ]]
	[[ " ${cmd[*]} " == *" $resolved/.git:/host/git:ro "* ]]
	[[ " ${cmd[*]} " == *"/talkbox/lib/merge.sh:ro"* ]]
	[[ " ${cmd[*]} " == *" talkbox/base:latest "* ]]
	local joined setup_prefix script_prefix
	joined="${cmd[*]}"
	setup_prefix="${joined%%setup.sh*}"
	script_prefix="${joined%%"$script"*}"
	[[ "$setup_prefix" != "$joined" ]]
	[[ "$script_prefix" != "$joined" ]]
	[[ "${#setup_prefix}" -lt "${#script_prefix}" ]]
	[[ " $joined " == *' master '* ]]
	[[ " $joined " == *' feature '* ]]
}

@test "container_sync_cmd no-network run opens with the exact prefix, --workdir directly after and the git mounts in order" {
	load_lib containers.sh
	local project="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$project"
	local base resolved script
	base="$(project_base "$project")"
	resolved="$(readlink -f "$project")"
	script='source /talkbox/lib/merge.sh'
	container_running() { return 1; }
	local -a cmd=()
	container_sync_cmd cmd "$project" onbox "$script" master
	[[ "${cmd[0]}" == podman ]]
	[[ "${cmd[1]}" == run ]]
	[[ "${cmd[2]}" == --rm ]]
	[[ "${cmd[3]}" == --network=none ]]
	[[ "${cmd[4]}" == --userns=keep-id:uid=1000,gid=1000 ]]
	[[ "${cmd[5]}" == "--workdir=/working/$base" ]]
	local -a specs=()
	local i
	for ((i = 0; i < ${#cmd[@]}; i++)); do
		if [[ "${cmd[i]}" == -v ]]; then
			specs+=("${cmd[i + 1]}")
		fi
	done
	[[ "${specs[*]}" == "proj.onbox.gitdir:/working/$base/.git $resolved:/working/$base $resolved/.git:/host/git:ro $TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro" ]]
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

# Function-based podman mock for exercising run_fetch/run_merge.
# PODMAN_VOLUMES lists existing volume names; PODMAN_FAIL_PATTERN/PODMAN_FAIL_CODE
# make matching invocations fail; mock_volume_mountpoint supplies volume mountpoints;
# mock_container_run executes the `podman run` bundle command.
podman() {
	printf '%s\n' "$*" >>"$PODMAN_LOG"
	if [[ -n "${PODMAN_FAIL_PATTERN:-}" && "$*" == *"$PODMAN_FAIL_PATTERN"* ]]; then
		return "${PODMAN_FAIL_CODE:-1}"
	fi
	case "$1 $2" in
	"volume exists")
		# shellcheck disable=SC2086 # word splitting over the volume list is intended
		local vol
		for vol in $PODMAN_VOLUMES; do
			[[ "$vol" == "$3" ]] && return 0
		done
		return 1
		;;
	"volume inspect")
		mock_volume_mountpoint "$5"
		;;
	"run "*)
		mock_container_run "$@"
		;;
	esac
	return 0
}

mock_volume_mountpoint() {
	printf '%s\n' "${PODMAN_MOUNTPOINTS[$1]:-}"
}

mock_container_run() {
	local -a args=("$@")
	local i spec vol repo="" hostdir="" name=""
	for ((i = 1; i < ${#args[@]}; i++)); do
		if [[ "${args[i]}" == -v ]]; then
			spec="${args[i + 1]}"
			case "$spec" in
			*:/gitdir:ro)
				vol="${spec%:/gitdir:ro}"
				repo="$(mock_volume_mountpoint "$vol")"
				;;
			*:/host/bundle)
				hostdir="${spec%:/host/bundle}"
				;;
			esac
		elif [[ "${args[i]}" == /host/bundle/* ]]; then
			name="${args[i]#/host/bundle/}"
		fi
	done
	[[ -n "$repo" && -n "$hostdir" && -n "$name" ]] || return 1
	git --git-dir="$repo" bundle create "$hostdir/$name" --all
}

bundle_tmp_dir_from_log() {
	local line word prev="" dir=""
	line="$(grep -m1 -- 'bundle create' "$PODMAN_LOG" || true)"
	# shellcheck disable=SC2086 # the logged command line is tokenised on purpose
	for word in $line; do
		if [[ "$prev" == -v && "$word" == *':/host/bundle' ]]; then
			dir="${word%:/host/bundle}"
		fi
		prev="$word"
	done
	printf '%s\n' "$dir"
}

@test "run_fetch dies with the no git history message when the gitdir volume is absent" {
	load_lib git.sh
	podman() { return 1; }
	local tmpbase="$BATS_TEST_TMPDIR/tmpscan"
	mkdir -p "$tmpbase"
	export TMPDIR="$tmpbase"
	run run_fetch "$WORK" onbox no
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox: no git history for onbox; create the container first'* ]]
	[[ -z "$(find "$tmpbase" -maxdepth 1 -name 'talkbox-fetch.*' -print -quit)" ]]
}

@test "run_fetch --all skips every container with a missing gitdir volume" {
	load_lib git.sh
	PODMAN_VOLUMES=""
	run run_fetch "$WORK" onbox yes
	[[ "$status" -eq 0 ]]
	[[ -z "$(git -C "$WORK" for-each-ref 'refs/remotes/onbox/*' 'refs/remotes/netbox/*' 'refs/remotes/offbox/*')" ]]
}

@test "run_fetch --all fetches only from containers whose gitdir volume exists" {
	load_lib git.sh
	PODMAN_VOLUMES="$VOL"
	PODMAN_MOUNTPOINTS["$VOL"]="$CTR_REPO/.git"
	git -C "$CTR_REPO" commit -q --allow-empty -m container-commit
	cd "$WORK"
	run run_fetch "$WORK" onbox yes
	[[ "$status" -eq 0 ]]
	[[ "$(git rev-parse "refs/remotes/onbox/$BRANCH")" == "$(git -C "$CTR_REPO" rev-parse HEAD)" ]]
	[[ -z "$(git for-each-ref 'refs/remotes/netbox/*' 'refs/remotes/offbox/*')" ]]
	local dir
	dir="$(bundle_tmp_dir_from_log)"
	[[ "$dir" == *'talkbox-fetch.'* ]]
	[[ ! -d "$dir" ]]
}

@test "run_fetch surfaces a failed bundle command as a non-zero result without fetching" {
	load_lib git.sh
	PODMAN_VOLUMES="$VOL"
	PODMAN_FAIL_PATTERN='bundle create'
	cd "$WORK"
	run run_fetch "$WORK" onbox no
	[[ "$status" -ne 0 ]]
	[[ -z "$(git for-each-ref 'refs/remotes/onbox/*')" ]]
	local dir
	dir="$(bundle_tmp_dir_from_log)"
	[[ "$dir" == *'talkbox-fetch.'* ]]
	[[ ! -d "$dir" ]]
}

@test "run_merge dies with the no git history message when the gitdir volume is absent" {
	load_lib git.sh
	cd "$WORK"
	run run_merge "$WORK" onbox no ''
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox: no git history for onbox; create the container first'* ]]
}

@test "run_merge dies with the start the container first message when the gitdir volume has no HEAD" {
	load_lib git.sh
	PODMAN_VOLUMES="$VOL"
	local empty_mp="$BATS_TEST_TMPDIR/empty-mount"
	mkdir -p "$empty_mp"
	PODMAN_MOUNTPOINTS["$VOL"]="$empty_mp"
	local head_before
	head_before="$(git -C "$WORK" rev-parse HEAD)"
	cd "$WORK"
	run run_merge "$WORK" onbox no ''
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox: no git history in the onbox gitdir volume; start the container first'* ]]
	[[ "$(git -C "$WORK" rev-parse HEAD)" == "$head_before" ]]
}

@test "run_merge fetches the container bundle and fast-forwards the current branch" {
	load_lib git.sh
	PODMAN_VOLUMES="$VOL"
	PODMAN_MOUNTPOINTS["$VOL"]="$CTR_REPO/.git"
	git -C "$CTR_REPO" commit -q --allow-empty -m container-commit
	local container_head
	container_head="$(git -C "$CTR_REPO" rev-parse HEAD)"
	cd "$WORK"
	run run_merge "$WORK" onbox no ''
	[[ "$status" -eq 0 ]]
	[[ "$(git rev-parse HEAD)" == "$container_head" ]]
	local dir
	dir="$(bundle_tmp_dir_from_log)"
	[[ "$dir" == *'talkbox-merge.'* ]]
	[[ ! -d "$dir" ]]
}

@test "run_merge surfaces a failed bundle command as a non-zero result without merging" {
	load_lib git.sh
	PODMAN_VOLUMES="$VOL"
	PODMAN_MOUNTPOINTS["$VOL"]="$CTR_REPO/.git"
	PODMAN_FAIL_PATTERN='bundle create'
	local head_before
	head_before="$(git -C "$WORK" rev-parse HEAD)"
	cd "$WORK"
	run run_merge "$WORK" onbox no ''
	[[ "$status" -ne 0 ]]
	[[ "$(git -C "$WORK" rev-parse HEAD)" == "$head_before" ]]
	local dir
	dir="$(bundle_tmp_dir_from_log)"
	[[ "$dir" == *'talkbox-merge.'* ]]
	[[ ! -d "$dir" ]]
}
