# shellcheck shell=bash

project_base() {
	local project="$1"
	local base
	base="${project%/}"
	printf '%s\n' "${base##*/}"
}

slugify() {
	local slug="$1"
	slug="${slug,,}"
	slug="${slug//[^a-z0-9]/-}"
	while [[ "$slug" == *--* ]]; do
		slug="${slug//--/-}"
	done
	slug="${slug#-}"
	slug="${slug%-}"
	printf '%s\n' "$slug"
}

project_slug() {
	slugify "$(project_base "$1")"
}

base_image_name() {
	printf '%s\n' "${TALKBOX_BASE_IMAGE:-talkbox/base:latest}"
}

dest_slug() {
	local dest="$1"
	dest="${dest#/}"
	dest="${dest%/}"
	slugify "$dest"
}

gitdir_volume() {
	printf '%s\n' "$(project_slug "$1").$2.gitdir"
}
