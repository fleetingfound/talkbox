#!/usr/bin/env bash
set -euo pipefail

if [[ -d /talkbox/dotfiles.global ]]; then
	cp -a /talkbox/dotfiles.global/. /home/dev/
fi
if [[ -d /talkbox/dotfiles.project ]]; then
	cp -a /talkbox/dotfiles.project/. /home/dev/
fi

if [[ -n "${TALKBOX_GIT_USER_NAME:-}" ]]; then
	git config --global user.name "$TALKBOX_GIT_USER_NAME"
fi
if [[ -n "${TALKBOX_GIT_USER_EMAIL:-}" ]]; then
	git config --global user.email "$TALKBOX_GIT_USER_EMAIL"
fi

ensure_host_remote() {
	local repo="$1"
	git -C "$repo" remote add host /host/git/ 2>/dev/null || git -C "$repo" remote set-url host /host/git/ 2>/dev/null || true
}

include_host_modules() {
	local repo="$1" src="/host/git/modules" dst config dir name path prefix
	dst="$repo/.git/modules"
	[[ -d "$src" ]] || return 0
	[[ -n "$(find "$src" -mindepth 1 -maxdepth 1 -print -quit)" ]] || return 0
	if [[ -d "$dst" ]]; then
		chmod -R u+w "$dst"
		rm -rf "$dst"
	fi
	cp -a "$src" "$dst"
	while IFS= read -r -d '' config; do
		dir="${config%/config}"
		name="${dir#"$dst"/}"
		path="$(git config --file "$repo/.gitmodules" --get "submodule.$name.path" 2>/dev/null || true)"
		if [[ -n "$path" ]]; then
			prefix="$(realpath -m --relative-to="$dir" "$repo")/"
			git config --file "$config" core.worktree "$prefix$path"
		fi
		chmod -R u-w "$dir/objects" "$dir/refs"
		if [[ -f "$dir/packed-refs" ]]; then
			chmod u-w "$dir/packed-refs"
		fi
	done < <(find "$dst" -type f -name config -print0)
}

if [[ -d /host/git ]]; then
	repo="$(pwd)"
	if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
		git init -q "$repo"
		ensure_host_remote "$repo"
		git -C "$repo" config core.worktree "$repo" 2>/dev/null || true
		if git -C "$repo" fetch host >/dev/null 2>&1; then
			host_branch="$(git --git-dir=/host/git symbolic-ref --short HEAD 2>/dev/null || true)"
			if [[ -n "$host_branch" ]] && git -C "$repo" rev-parse --verify "refs/remotes/host/$host_branch" >/dev/null 2>&1; then
				git -C "$repo" symbolic-ref HEAD "refs/heads/$host_branch"
				git -C "$repo" reset --mixed "refs/remotes/host/$host_branch" >/dev/null 2>&1 || true
			fi
		fi
	else
		ensure_host_remote "$repo"
	fi
	include_host_modules "$repo"
fi
