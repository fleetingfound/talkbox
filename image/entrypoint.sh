#!/usr/bin/env bash
set -euo pipefail

if [[ -d /talkbox/dotfiles.global ]]; then
	cp -a /talkbox/dotfiles.global/. /home/dev/
fi
if [[ -d /talkbox/dotfiles.project ]]; then
	cp -a /talkbox/dotfiles.project/. /home/dev/
fi

if [[ $# -gt 0 ]]; then
	exec bash -c "$*"
fi
exec /bin/bash
