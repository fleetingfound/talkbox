#!/usr/bin/env bash
set -euo pipefail

die() {
	local message="$1" code="${2:-1}"
	printf 'release: %s\n' "$message" >&2
	exit "$code"
}

print_help() {
	cat <<'EOF'
usage: release.sh <version>

Cut a release from the current dev commit. The main commit carries the dev tree
minus every path matched by .coreignore (parsed with git's gitignore rules),
a subject containing the version, the user-edited release notes, a trailing
'Commit: <dev hash>' line and the author and committer timestamps of the dev
commit. The main commit is tagged v<version> and the dev commit dev/v<version>,
both as lightweight tags, so the tag timestamps are those of the commits they
point to.

The version argument may carry a leading v (v0.1.3 or 0.1.3). The script must
be run on the dev branch with a clean worktree. Nothing is pushed; push main
and the tags manually afterwards.
EOF
}

normalize_version() {
	local version="${1#v}"
	[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || die "invalid version '$1'"
	printf '%s' "$version"
}

validate_release_state() {
	local version="$1" branch main_checkout
	branch="$(git symbolic-ref --quiet --short HEAD)" || die 'HEAD is not on a branch; releases are cut from dev'
	[[ "$branch" == dev ]] || die "current branch is '$branch'; releases are cut from dev"
	[[ -z "$(git status --porcelain)" ]] || die 'worktree is not clean relative to dev HEAD; commit or stash first'
	git show-ref --verify --quiet refs/heads/main || die 'branch main does not exist'
	git rev-parse -q --verify "refs/tags/v$version" >/dev/null && die "tag v$version already exists"
	git rev-parse -q --verify "refs/tags/dev/v$version" >/dev/null && die "tag dev/v$version already exists"
	main_checkout="$(git worktree list --porcelain | grep '^branch refs/heads/main$')" || true
	[[ -z "$main_checkout" ]] || die 'main is checked out in another worktree; release from a worktree on dev only'
}

extract_coreignore() {
	local dev_hash="$1" coreignore_file="$2"
	if git cat-file -e "$dev_hash:.coreignore" 2>/dev/null; then
		git show "$dev_hash:.coreignore" >"$coreignore_file"
	else
		: >"$coreignore_file"
	fi
}

write_dev_tree_paths() {
	local dev_hash="$1" entry type path
	while IFS= read -r -d '' entry; do
		type="${entry#* }"
		type="${type%% *}"
		path="${entry#*$'\t'}"
		if [[ "$type" == commit ]]; then
			printf '%s/\0' "$path"
		else
			printf '%s\0' "$path"
		fi
	done < <(git ls-tree -r -z "$dev_hash")
}

write_ignored_paths() {
	local dev_hash="$1" coreignore_file="$2" out_file="$3"
	local hermetic_dir="$tmp_dir/hermetic" raw_file="$tmp_dir/ignored.raw" status=0 path
	mkdir -p "$hermetic_dir/git/objects" "$hermetic_dir/git/refs" "$hermetic_dir/worktree"
	printf 'ref: refs/heads/dev\n' >"$hermetic_dir/git/HEAD"
	write_dev_tree_paths "$dev_hash" |
		GIT_DIR="$hermetic_dir/git" GIT_WORK_TREE="$hermetic_dir/worktree" \
			git -c core.excludesFile="$coreignore_file" check-ignore --stdin -z --no-index \
			>"$raw_file" || status=$?
	((status <= 1)) || die "git check-ignore failed with status $status"
	while IFS= read -r -d '' path; do
		printf '%s\0' "${path%/}"
	done <"$raw_file" >"$out_file"
}

build_main_tree() {
	local dev_hash="$1" ignored_file="$2"
	local index_file="$tmp_dir/index"
	GIT_INDEX_FILE="$index_file" git read-tree "$dev_hash"
	GIT_INDEX_FILE="$index_file" git update-index --force-remove -z --stdin <"$ignored_file"
	GIT_INDEX_FILE="$index_file" git write-tree
}

edit_message() {
	local version="$1" dev_hash="$2" message_file="$3"
	local editor
	{
		printf 'talkbox v%s\n\n' "$version"
		printf '# release notes: one bullet per line\n'
		printf '# lines starting with # are removed; the release aborts if no notes remain\n'
		printf 'Commit: %s\n' "$dev_hash"
	} >"$message_file"
	editor="${GIT_EDITOR:-${EDITOR:-vi}}"
	sh -c "$editor \"\$@\"" "$editor" "$message_file" || die "editor '$editor' exited with a non-zero status"
}

finalize_message() {
	local version="$1" dev_hash="$2" message_file="$3"
	local -a lines=() body=() final=()
	local i line seen_notes=no blank_run=no
	mapfile -t lines <"$message_file"
	while ((${#lines[@]} > 0)) && [[ -z "${lines[${#lines[@]} - 1]}" ]]; do
		unset "lines[${#lines[@]} - 1]"
	done
	((${#lines[@]} >= 2)) || die "edited message is empty or missing the 'Commit: $dev_hash' line"
	[[ "${lines[${#lines[@]} - 1]}" == "Commit: $dev_hash" ]] || die "message must end with the 'Commit: $dev_hash' line"
	[[ "${lines[0]}" == *"v$version"* ]] || die "subject must contain v$version"
	for ((i = 1; i < ${#lines[@]} - 1; i++)); do
		line="${lines[i]}"
		[[ "$line" == \#* ]] && continue
		if [[ -z "$line" ]]; then
			if [[ "$seen_notes" == yes && "$blank_run" == no ]]; then
				body+=('')
				blank_run=yes
			fi
			continue
		fi
		seen_notes=yes
		blank_run=no
		body+=("$line")
	done
	[[ "$seen_notes" == yes ]] || die 'no release notes: add notes between the subject and the Commit: line'
	while ((${#body[@]} > 0)) && [[ -z "${body[${#body[@]} - 1]}" ]]; do
		unset "body[${#body[@]} - 1]"
	done
	final=("${lines[0]}" '')
	for line in "${body[@]}"; do
		final+=("$line")
	done
	final+=('' "${lines[${#lines[@]} - 1]}")
	printf '%s\n' "${final[@]}" >"$message_file"
}

run_release() {
	local version="$1"
	local toplevel dev_hash coreignore_file ignored_file main_tree
	local message_file main_parent main_commit dev_author_date dev_commit_date
	if [[ "$version" == -h || "$version" == --help ]]; then
		print_help
		exit 0
	fi
	version="$(normalize_version "$version")"
	toplevel="$(git rev-parse --show-toplevel)" || die 'not inside a git repository'
	cd "$toplevel"
	validate_release_state "$version"
	dev_hash="$(git rev-parse HEAD)"
	dev_author_date="$(git show -s --format=%aI "$dev_hash")"
	dev_commit_date="$(git show -s --format=%cI "$dev_hash")"
	coreignore_file="$tmp_dir/coreignore"
	extract_coreignore "$dev_hash" "$coreignore_file"
	ignored_file="$tmp_dir/ignored"
	write_ignored_paths "$dev_hash" "$coreignore_file" "$ignored_file"
	main_tree="$(build_main_tree "$dev_hash" "$ignored_file")"
	message_file="$tmp_dir/message"
	edit_message "$version" "$dev_hash" "$message_file"
	finalize_message "$version" "$dev_hash" "$message_file"
	main_parent="$(git rev-parse refs/heads/main)"
	main_commit="$(GIT_AUTHOR_DATE="$dev_author_date" GIT_COMMITTER_DATE="$dev_commit_date" \
		git commit-tree "$main_tree" -p "$main_parent" -F "$message_file")" || die 'git commit-tree failed'
	git update-ref refs/heads/main "$main_commit" "$main_parent" || die 'failed to advance main'
	git tag "v$version" "$main_commit" || die "failed to create tag v$version"
	git tag "dev/v$version" "$dev_hash" || die "failed to create tag dev/v$version"
	printf 'release: main commit %s\n' "$main_commit"
	printf 'release: dev commit %s\n' "$dev_hash"
	printf 'release: tags v%s and dev/v%s\n' "$version" "$version"
	printf 'release: push main and the tags when ready; no push is performed\n'
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

(($# == 1)) || {
	print_help >&2
	die 'expected exactly one <version> argument' 2
}
run_release "$1"
