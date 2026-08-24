# shellcheck shell=bash

warn() {
	printf 'talkbox: %s\n' "$1" >&2
}

ref_exists() {
	local ref="$1"
	git show-ref --verify --quiet "$ref"
}

# DESCENDANT_CHECK: when refs/heads/<branchname> exists it passes only if
# refs/remotes/<remote>/<branchname> exists and is a descendant of it; when the
# branch does not exist it passes regardless.
descendant_check() {
	local remote="$1" branchname="$2" head_ref remote_ref
	head_ref="refs/heads/$branchname"
	remote_ref="refs/remotes/$remote/$branchname"
	if ! ref_exists "$head_ref"; then
		return 0
	fi
	if ! ref_exists "$remote_ref"; then
		return 1
	fi
	git merge-base --is-ancestor "$head_ref" "$remote_ref"
}

custom_merge() {
	local remote="$1" branchname="$2" current
	if ! descendant_check "$remote" "$branchname"; then
		warn "refusing to merge $branchname from $remote: not a descendant"
		return 1
	fi
	current="$(git symbolic-ref -q --short HEAD 2>/dev/null || true)"
	if [[ "$current" == "$branchname" ]]; then
		custom_merge_current "$remote" "$branchname"
	else
		if ! ref_exists "refs/remotes/$remote/$branchname"; then
			warn "refusing to merge $branchname from $remote: the remote branch does not exist"
			return 1
		fi
		git branch -f "$branchname" "refs/remotes/$remote/$branchname"
	fi
}

worktree_matches_tree() {
	local ref="$1" tmp_index worktree_tree remote_tree
	tmp_index="$(mktemp "${TMPDIR:-/tmp}/talkbox-index.XXXXXX")"
	rm -f "$tmp_index"
	if ! GIT_INDEX_FILE="$tmp_index" git add -A >/dev/null 2>&1; then
		rm -f "$tmp_index"
		return 1
	fi
	worktree_tree="$(GIT_INDEX_FILE="$tmp_index" git write-tree 2>/dev/null)"
	rm -f "$tmp_index"
	remote_tree="$(git rev-parse "$ref^{tree}" 2>/dev/null)" || return 1
	[[ "$worktree_tree" == "$remote_tree" ]]
}

custom_merge_current() {
	local remote="$1" branchname="$2" remote_ref
	remote_ref="refs/remotes/$remote/$branchname"
	if git diff --cached --quiet && git diff --quiet; then
		git merge --ff-only "$remote_ref"
	elif git diff --cached --quiet && worktree_matches_tree "$remote_ref"; then
		git reset --mixed "$remote_ref"
	else
		warn "refusing to merge $branchname from $remote: the working tree has changes"
		return 1
	fi
}
