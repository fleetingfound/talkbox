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

if [[ -d /host/git ]]; then
	repo="$(pwd)"
	if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
		git init -q "$repo"
		git -C "$repo" remote add host /host/git/ 2>/dev/null || git -C "$repo" remote set-url host /host/git/ 2>/dev/null || true
		git -C "$repo" config core.worktree "$repo" 2>/dev/null || true
		if git -C "$repo" fetch host >/dev/null 2>&1; then
			host_branch="$(git --git-dir=/host/git symbolic-ref --short HEAD 2>/dev/null || true)"
			if [[ -n "$host_branch" ]] && git -C "$repo" rev-parse --verify "refs/remotes/host/$host_branch" >/dev/null 2>&1; then
				git -C "$repo" symbolic-ref HEAD "refs/heads/$host_branch"
				git -C "$repo" reset --mixed "refs/remotes/host/$host_branch" >/dev/null 2>&1 || true
			fi
		fi
	else
		git -C "$repo" remote set-url host /host/git/ 2>/dev/null || git -C "$repo" remote add host /host/git/ 2>/dev/null || true
	fi
fi

if [[ $# -gt 0 ]]; then
	exec bash -c "$*"
fi
exec /bin/bash
