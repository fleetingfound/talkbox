# shellcheck shell=bash

project_base() {
	local project="$1"
	local base
	base="${project%/}"
	printf '%s\n' "${base##*/}"
}

project_slug() {
	local base
	base="$(project_base "$1")"
	base="${base,,}"
	base="${base//[^a-z0-9]/-}"
	while [[ "$base" == *--* ]]; do
		base="${base//--/-}"
	done
	base="${base#-}"
	base="${base%-}"
	printf '%s\n' "$base"
}

base_image_name() {
	printf '%s\n' 'talkbox/base:latest'
}
