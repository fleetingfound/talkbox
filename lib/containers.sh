#!/usr/bin/env bash

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/naming.sh"

plan_onbox() {
	local project="$1" command="$2" interactive="$3"
	local base
	base="$(project_base "$project")"
	printf -- '--workdir=/working/%s\n' "$base"
	printf '%s\n' '--userns=keep-id:uid=1000,gid=1000'
	printf '%s\n' '--network=pasta'
	printf '%s\n' '--cap-drop=NET_ADMIN'
	printf '%s\n' '--cap-drop=NET_RAW'
	printf -- '-v %s:/working/%s\n' "$project" "$base"
	printf -- '-v %s/defaults/dotfiles:/talkbox/dotfiles.global:ro\n' "$TALKBOX_ROOT"
	printf -- '-v %s/.dotfiles:/talkbox/dotfiles.project:ro\n' "$project"
	printf '%s\n' '--rm'
	if [[ "$interactive" == yes ]]; then
		printf '%s\n' '--interactive'
		printf '%s\n' '--tty'
	fi
	printf '%s\n' "$(base_image_name)"
	if [[ -n "$command" ]]; then
		printf '%s\n' "$command"
	fi
}

ensure_base_image() {
	if ! podman image exists "$(base_image_name)" >/dev/null 2>&1; then
		podman build -t "$(base_image_name)" -f "$TALKBOX_ROOT/image/Containerfile" "$TALKBOX_ROOT/image"
	fi
}

run_onbox() {
	local project="$1" command="$2" interactive="$3"
	local args=() line
	while IFS= read -r line; do
		if [[ "$line" == "-v $project/.dotfiles:"* && ! -d "$project/.dotfiles" ]]; then
			continue
		fi
		if [[ "$line" == -v\ * ]]; then
			args+=("-v" "${line#-v }")
		else
			args+=("$line")
		fi
	done < <(plan_onbox "$project" "$command" "$interactive")
	podman run "${args[@]}"
}
