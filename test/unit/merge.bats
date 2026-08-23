# shellcheck disable=SC2030,SC2031 # bats runs setup/test/teardown in one subshell; BRANCH is read within the test
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
	git -C "$WORK" remote add origin "$REMOTE"
	git -C "$WORK" push -q origin HEAD
	git -C "$WORK" fetch -q origin
}

# Create a commit on a throwaway branch and push it to origin as <branch>,
# leaving the checked-out branch and its worktree untouched, then refresh the
# remote-tracking refs.
push_descendant() {
	local branch="$1" content="$2" tmp
	tmp="advance-$(basename "$branch")"
	git -C "$WORK" switch -q -c "$tmp"
	printf '%s\n' "$content" >"$WORK/file.txt"
	git -C "$WORK" commit -qa -m "advance $branch"
	git -C "$WORK" push -q origin "HEAD:$branch"
	git -C "$WORK" switch -q -
	git -C "$WORK" branch -q -D "$tmp"
	git -C "$WORK" fetch -q origin
}

@test "custom_merge fast-forwards a clean current branch (Case 1)" {
	load_lib git.sh
	push_descendant "$BRANCH" two
	local remote_sha
	remote_sha="$(git -C "$WORK" rev-parse "refs/remotes/origin/$BRANCH")"
	cd "$WORK"
	run custom_merge origin "$BRANCH"
	[[ "$status" -eq 0 ]]
	[[ "$(git -C "$WORK" rev-parse HEAD)" == "$remote_sha" ]]
	[[ "$(git -C "$WORK" rev-parse "$BRANCH")" == "$remote_sha" ]]
	[[ "$(cat "$WORK/file.txt")" == "two" ]]
	[[ -z "$(git -C "$WORK" status --porcelain)" ]]
}

@test "custom_merge updates the branch when the worktree already matches the remote (Case 2)" {
	load_lib git.sh
	push_descendant "$BRANCH" two
	local remote_sha head_before
	remote_sha="$(git -C "$WORK" rev-parse "refs/remotes/origin/$BRANCH")"
	head_before="$(git -C "$WORK" rev-parse HEAD)"
	[[ "$head_before" != "$remote_sha" ]]
	printf 'two\n' >"$WORK/file.txt"
	cd "$WORK"
	run custom_merge origin "$BRANCH"
	[[ "$status" -eq 0 ]]
	[[ "$(git -C "$WORK" rev-parse HEAD)" == "$remote_sha" ]]
	[[ "$(cat "$WORK/file.txt")" == "two" ]]
	[[ -z "$(git -C "$WORK" status --porcelain)" ]]
}

@test "custom_merge leaves a dirty worktree untouched and warns (Case 3)" {
	load_lib git.sh
	push_descendant "$BRANCH" two
	local head_before
	head_before="$(git -C "$WORK" rev-parse HEAD)"
	printf 'dirty\n' >"$WORK/file.txt"
	cd "$WORK"
	run custom_merge origin "$BRANCH"
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(git -C "$WORK" rev-parse HEAD)" == "$head_before" ]]
	[[ "$(cat "$WORK/file.txt")" == "dirty" ]]
}

@test "custom_merge warns and makes no change when the remote branch is not a descendant" {
	load_lib git.sh
	local head_before
	printf 'local\n' >"$WORK/file.txt"
	git -C "$WORK" add file.txt
	git -C "$WORK" commit -q -m local-advance
	head_before="$(git -C "$WORK" rev-parse HEAD)"
	cd "$WORK"
	run custom_merge origin "$BRANCH"
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(git -C "$WORK" rev-parse HEAD)" == "$head_before" ]]
	[[ -z "$(git -C "$WORK" status --porcelain)" ]]
}

@test "custom_merge warns and makes no change when the remote-tracking branch is absent" {
	load_lib git.sh
	git -C "$WORK" branch -q feature
	local feature_head current
	feature_head="$(git -C "$WORK" rev-parse feature)"
	current="$(git -C "$WORK" symbolic-ref --short HEAD)"
	cd "$WORK"
	run custom_merge origin feature
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(git -C "$WORK" rev-parse feature)" == "$feature_head" ]]
	[[ "$(git -C "$WORK" symbolic-ref --short HEAD)" == "$current" ]]
}

@test "custom_merge creates a new branch without switching when the branch does not exist" {
	load_lib git.sh
	push_descendant feature two
	local feature_sha current
	feature_sha="$(git -C "$WORK" rev-parse "refs/remotes/origin/feature")"
	current="$(git -C "$WORK" symbolic-ref --short HEAD)"
	cd "$WORK"
	run custom_merge origin feature
	[[ "$status" -eq 0 ]]
	[[ "$(git -C "$WORK" rev-parse "refs/heads/feature")" == "$feature_sha" ]]
	[[ "$(git -C "$WORK" symbolic-ref --short HEAD)" == "$current" ]]
}

@test "custom_merge advances an existing non-current branch without switching" {
	load_lib git.sh
	git -C "$WORK" branch -q feature
	push_descendant feature two
	local feature_after current
	feature_after="$(git -C "$WORK" rev-parse "refs/remotes/origin/feature")"
	current="$(git -C "$WORK" symbolic-ref --short HEAD)"
	cd "$WORK"
	run custom_merge origin feature
	[[ "$status" -eq 0 ]]
	[[ "$(git -C "$WORK" rev-parse "refs/heads/feature")" == "$feature_after" ]]
	[[ "$(git -C "$WORK" symbolic-ref --short HEAD)" == "$current" ]]
}
