load helpers

setup() {
	PROJECT="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$PROJECT"
}

@test "git_tracked succeeds for a project with a .git directory" {
	load_lib git.sh
	mkdir -p "$PROJECT/.git"
	run git_tracked "$PROJECT"
	[[ "$status" -eq 0 ]]
}

@test "git_tracked succeeds for a project whose .git is a gitdir file" {
	load_lib git.sh
	printf 'gitdir: %s/.git\n' "$BATS_TEST_TMPDIR/elsewhere" >"$PROJECT/.git"
	run git_tracked "$PROJECT"
	[[ "$status" -eq 0 ]]
}

@test "git_tracked fails for a project without .git" {
	load_lib git.sh
	run git_tracked "$PROJECT"
	[[ "$status" -ne 0 ]]
}

@test "resolve_git_dir prints the project .git directory for a plain repository" {
	load_lib git.sh
	mkdir -p "$PROJECT/.git"
	[[ "$(resolve_git_dir "$PROJECT")" == "$PROJECT/.git" ]]
}

@test "resolve_git_dir follows an absolute gitdir file to a path outside the project" {
	load_lib git.sh
	mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
	printf 'gitdir: %s/.git\n' "$BATS_TEST_TMPDIR/elsewhere" >"$PROJECT/.git"
	[[ "$(resolve_git_dir "$PROJECT")" == "$BATS_TEST_TMPDIR/elsewhere/.git" ]]
}

@test "resolve_git_dir follows a relative gitdir file from the project directory" {
	load_lib git.sh
	mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
	printf 'gitdir: ../elsewhere\n' >"$PROJECT/.git"
	[[ "$(resolve_git_dir "$PROJECT")" == "$BATS_TEST_TMPDIR/elsewhere" ]]
}

@test "classify_git_dir prints inside for a project with an internal .git directory" {
	load_lib git.sh
	mkdir -p "$PROJECT/.git"
	[[ "$(classify_git_dir "$PROJECT")" == inside ]]
}

@test "classify_git_dir prints outside when the gitdir file points outside the project" {
	load_lib git.sh
	mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
	printf 'gitdir: %s/.git\n' "$BATS_TEST_TMPDIR/elsewhere" >"$PROJECT/.git"
	[[ "$(classify_git_dir "$PROJECT")" == outside ]]
}

@test "classify_git_dir treats a sibling gitdir outside the project as outside" {
	load_lib git.sh
	sibling="$BATS_TEST_TMPDIR/proj-other"
	mkdir -p "$sibling"
	printf 'gitdir: %s/.git\n' "$sibling" >"$PROJECT/.git"
	[[ "$(classify_git_dir "$PROJECT")" == outside ]]
}

@test "classify_git_dir prints none for a non-git project" {
	load_lib git.sh
	[[ "$(classify_git_dir "$PROJECT")" == none ]]
}

@test "list_submodule_git_dirs lists the submodule git dirs under the top-level git dir" {
	load_lib git.sh
	mkdir -p "$PROJECT/.git/modules/sub1" "$PROJECT/.git/modules/sub2"
	[[ "$(list_submodule_git_dirs "$PROJECT")" == "$PROJECT/.git/modules/sub1
$PROJECT/.git/modules/sub2" ]]
}

@test "list_submodule_git_dirs yields nothing when the git dir has no submodules" {
	load_lib git.sh
	mkdir -p "$PROJECT/.git"
	[[ -z "$(list_submodule_git_dirs "$PROJECT")" ]]
}

@test "current_branch on a detached HEAD produces a talkbox error" {
	load_lib git.sh
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.email test@example.com
	git -C "$PROJECT" config user.name talkbox-test
	printf 'x\n' >"$PROJECT/f.txt"
	git -C "$PROJECT" add f.txt
	git -C "$PROJECT" commit -q -m initial
	git -C "$PROJECT" checkout -q --detach
	cd "$PROJECT"
	run current_branch
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$output" != *'fatal:'* ]]
}

@test "plan_fetch builds a no-network gitdir bundle command against the container gitdir volume" {
	load_lib git.sh
	load_lib naming.sh
	local -a bundle_cmd=() fetch_cmd=()
	plan_fetch bundle_cmd fetch_cmd "$PROJECT" onbox "$BATS_TEST_TMPDIR/onbox.bundle"
	[[ "${bundle_cmd[*]}" == *'podman run --rm --network=none'* ]]
	[[ "${bundle_cmd[*]}" == *'proj.onbox.gitdir:/gitdir:ro'* ]]
	[[ "${bundle_cmd[*]}" == *'git bundle create'* ]]
}

@test "plan_fetch fetches the bundle into the host repo under refs/remotes/<container>" {
	load_lib git.sh
	load_lib naming.sh
	local -a bundle_cmd=() fetch_cmd=()
	plan_fetch bundle_cmd fetch_cmd "$PROJECT" netbox "$BATS_TEST_TMPDIR/netbox.bundle"
	[[ "${fetch_cmd[*]}" == *'git fetch'* ]]
	[[ "${fetch_cmd[*]}" == *'refs/remotes/netbox'* ]]
	[[ "${fetch_cmd[*]}" == *'netbox.bundle'* ]]
}
