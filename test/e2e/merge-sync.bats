# shellcheck disable=SC2030,SC2031 # bats runs setup/test/teardown in one subshell; EXTRA_DIRS is read back in teardown
load helpers

setup() {
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"
	ONBOX_CTR="$PROJECT_SLUG.onbox"
	PLAIN_CTR=""
	EXTRA_DIRS=()
	BRANCH="$(git -C "$PROJECT" symbolic-ref --short HEAD)"
	GITDIR_VOL="$PROJECT_SLUG.onbox.gitdir"
	printf 'tracked\n' >"$PROJECT/file.txt"
	git -C "$PROJECT" add file.txt
	git -C "$PROJECT" commit -q -m host-initial
}

teardown() {
	teardown_talkbox "$PROJECT_SLUG" "$PLAIN_CTR"
	rm -rf "$PROJECT" "$TALKBOX" "${EXTRA_DIRS[@]}"
}

volume_mountpoint() {
	sdrun podman volume inspect --format '{{.Mountpoint}}' "$1" 2>/dev/null || true
}

container_stopped() {
	local state
	state="$(sdrun podman inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -x 'false' || true)"
	[[ "$state" == 'false' ]]
}

container_commit() {
	local message="$1"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git config user.email c@example.com && git config user.name container && git commit --allow-empty -m '"$message"
	[[ "$status" -eq 0 ]]
}

@test "onbox fetch then onbox merge brings a container commit into the host worktree" {
	container_commit container-merge-commit
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge
	[[ "$status" -eq 0 ]]
	run git -C "$PROJECT" log --oneline -1
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'container-merge-commit'* ]]
}

@test "onbox merge <branchname> merges the named branch without switching" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git config user.email c@example.com && git config user.name container && git checkout -q -b feature && git commit --allow-empty -m feature-commit'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge feature
	[[ "$status" -eq 0 ]]
	run git -C "$PROJECT" log --oneline feature
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'feature-commit'* ]]
	run git -C "$PROJECT" symbolic-ref --short HEAD
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$BRANCH" ]]
}

@test "onbox merge --all applies custom_merge across all onbox branches" {
	container_commit branch-a-commit
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git config user.email c@example.com && git config user.name container && git checkout -q -b feature && git commit --allow-empty -m branch-b-commit'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge --all
	[[ "$status" -eq 0 ]]
	run git -C "$PROJECT" log --oneline "$BRANCH"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'branch-a-commit'* ]]
	run git -C "$PROJECT" log --oneline feature
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'branch-b-commit'* ]]
}

@test "onbox merge fast-forwards with an untracked file in the host worktree" {
	container_commit container-untracked-merge
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	printf 'untracked\n' >"$PROJECT/untracked.txt"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge
	[[ "$status" -eq 0 ]]
	run git -C "$PROJECT" log --oneline -1
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'container-untracked-merge'* ]]
	[[ -e "$PROJECT/untracked.txt" ]]
	[[ "$(cat "$PROJECT/untracked.txt")" == 'untracked' ]]
}

@test "onbox merge fast-forwards when the container commit introduces a file untracked in the host worktree" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive \
		'git config user.email c@example.com && git config user.name container && printf "container\n" >new-file.txt && git add new-file.txt && git commit -q -m container-new-file-commit'
	[[ "$status" -eq 0 ]]
	[[ "$(cat "$PROJECT/new-file.txt")" == 'container' ]]
	run git -C "$PROJECT" status --porcelain
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'new-file.txt'* ]]
	local host_head
	host_head="$(git -C "$PROJECT" rev-parse HEAD)"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge
	[[ "$status" -eq 0 ]]
	[[ "$(git -C "$PROJECT" rev-parse HEAD)" != "$host_head" ]]
	run git -C "$PROJECT" log --oneline -1
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'container-new-file-commit'* ]]
	[[ "$(cat "$PROJECT/new-file.txt")" == 'container' ]]
}

@test "onbox merge --all stops at the first failing branch and skips the rest" {
	git -C "$PROJECT" checkout -q -b feature
	printf 'host-feature\n' >"$PROJECT/feature.txt"
	git -C "$PROJECT" add feature.txt
	git -C "$PROJECT" commit -q -m host-feature
	git -C "$PROJECT" checkout -q "$BRANCH"
	git -C "$PROJECT" branch -q later
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive \
		"git config user.email c@example.com && git config user.name container && git checkout -q -b feature && git commit --allow-empty -m container-feature && git checkout -q \"$BRANCH\" && git checkout -q -b later && git commit --allow-empty -m container-later && git checkout -q \"$BRANCH\" && git commit --allow-empty -m container-current"
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	local feature_before later_before current_before remote_later remote_current
	feature_before="$(git -C "$PROJECT" rev-parse refs/heads/feature)"
	later_before="$(git -C "$PROJECT" rev-parse refs/heads/later)"
	current_before="$(git -C "$PROJECT" rev-parse HEAD)"
	remote_later="$(git -C "$PROJECT" rev-parse "refs/remotes/onbox/later")"
	remote_current="$(git -C "$PROJECT" rev-parse "refs/remotes/onbox/$BRANCH")"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge --all
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(git -C "$PROJECT" rev-parse refs/heads/feature)" == "$feature_before" ]]
	[[ "$(git -C "$PROJECT" rev-parse refs/heads/later)" == "$later_before" ]]
	[[ "$(git -C "$PROJECT" rev-parse HEAD)" == "$current_before" ]]
	[[ "$remote_later" != "$later_before" ]]
	[[ "$remote_current" != "$current_before" ]]
}

@test "onbox merge leaves a dirty host worktree untouched and warns" {
	container_commit container-dirty-commit
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	printf 'dirty\n' >"$PROJECT/file.txt"
	local host_head
	host_head="$(git -C "$PROJECT" rev-parse HEAD)"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(git -C "$PROJECT" rev-parse HEAD)" == "$host_head" ]]
	[[ "$(cat "$PROJECT/file.txt")" == 'dirty' ]]
}

@test "onbox merge refuses a non-descendant with a warning and leaves HEAD unchanged" {
	container_commit container-side-commit
	printf 'host-side\n' >"$PROJECT/host-side.txt"
	git -C "$PROJECT" add host-side.txt
	git -C "$PROJECT" commit -q -m host-side-commit
	local host_head
	host_head="$(git -C "$PROJECT" rev-parse HEAD)"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(git -C "$PROJECT" rev-parse HEAD)" == "$host_head" ]]
	[[ -z "$(git -C "$PROJECT" status --porcelain)" ]]
}

@test "onbox merge <nonexistent-branch> warns with a talkbox message and exits non-zero" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge nosuchbranch
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$output" != *'fatal:'* ]]
}

@test "onbox merge with a detached host HEAD errors with a talkbox message and exits non-zero" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	git -C "$PROJECT" checkout -q --detach
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$output" != *'fatal:'* ]]
}

@test "onbox merge on an uninitialised gitdir volume errors with a talkbox message" {
	sdrun podman volume create "$PROJECT_SLUG.onbox.gitdir" >/dev/null
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$output" != *'fatal:'* ]]
}

@test "onbox sync brings a host commit into the onbox gitdir volume" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	printf 'host-work\n' >"$PROJECT/file.txt"
	git -C "$PROJECT" add file.txt
	git -C "$PROJECT" commit -q -m host-commit-sync
	local host_head
	host_head="$(git -C "$PROJECT" rev-parse HEAD)"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox sync
	[[ "$status" -eq 0 ]]
	local mp
	mp="$(volume_mountpoint "$GITDIR_VOL")"
	[[ -n "$mp" ]]
	local vol_head
	vol_head="$(cat "$mp/refs/heads/$BRANCH")"
	[[ "$host_head" == "$vol_head" ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git log --oneline'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'host-commit-sync'* ]]
}

@test "onbox sync --all syncs all host branches into the onbox gitdir volume" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	git -C "$PROJECT" checkout -q -b feature
	printf 'feature\n' >"$PROJECT/feature.txt"
	git -C "$PROJECT" add feature.txt
	git -C "$PROJECT" commit -q -m host-feature-sync
	git -C "$PROJECT" checkout -q "$BRANCH"
	git -C "$PROJECT" commit -q --allow-empty -m host-current-sync
	local host_current host_feature
	host_current="$(git -C "$PROJECT" rev-parse HEAD)"
	host_feature="$(git -C "$PROJECT" rev-parse feature)"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox sync --all
	[[ "$status" -eq 0 ]]
	local mp
	mp="$(volume_mountpoint "$GITDIR_VOL")"
	[[ -n "$mp" ]]
	[[ "$(cat "$mp/refs/heads/$BRANCH")" == "$host_current" ]]
	[[ "$(cat "$mp/refs/heads/feature")" == "$host_feature" ]]
}

@test "onbox sync <branchname> syncs the named host branch into the onbox gitdir volume" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	git -C "$PROJECT" checkout -q -b feature
	printf 'feature\n' >"$PROJECT/feature.txt"
	git -C "$PROJECT" add feature.txt
	git -C "$PROJECT" commit -q -m host-feature-sync
	git -C "$PROJECT" checkout -q "$BRANCH"
	local host_feature
	host_feature="$(git -C "$PROJECT" rev-parse feature)"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox sync feature
	[[ "$status" -eq 0 ]]
	local mp
	mp="$(volume_mountpoint "$GITDIR_VOL")"
	[[ -n "$mp" ]]
	[[ "$(cat "$mp/refs/heads/feature")" == "$host_feature" ]]
	run git -C "$PROJECT" symbolic-ref --short HEAD
	[[ "$output" == "$BRANCH" ]]
}

@test "onbox sync uses the temporary-container path when the onbox container is stopped" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	container_stopped "$ONBOX_CTR"
	printf 'host-work\n' >"$PROJECT/file.txt"
	git -C "$PROJECT" add file.txt
	git -C "$PROJECT" commit -q -m host-commit-stopped-sync
	local host_head
	host_head="$(git -C "$PROJECT" rev-parse HEAD)"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox sync
	[[ "$status" -eq 0 ]]
	local mp
	mp="$(volume_mountpoint "$GITDIR_VOL")"
	[[ -n "$mp" ]]
	[[ "$(cat "$mp/refs/heads/$BRANCH")" == "$host_head" ]]
	container_stopped "$ONBOX_CTR"
}

@test "onbox merge --all creates new local branches for container-only branches" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive \
		"git config user.email c@example.com && git config user.name container && git checkout -q -b container-only && git commit --allow-empty -m container-only-commit && git checkout -q \"$BRANCH\""
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox fetch
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" onbox merge --all
	[[ "$status" -eq 0 ]]
	run git -C "$PROJECT" log --oneline container-only
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'container-only-commit'* ]]
	run git -C "$PROJECT" symbolic-ref --short HEAD
	[[ "$output" == "$BRANCH" ]]
}
